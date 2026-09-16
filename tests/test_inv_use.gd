@tool
extends McpTestSuite

## InvUsableComponent: use_slot / InvHotbar.use_active result handling,
## policy gating, can_use, data mutation + refresh (touch), signals.


class Food extends InvUsableComponent:
	var restores: int = 25
	func _init() -> void:
		data_key = &"food"
		use_label = "Eat"
	func can_use(_s: InvItemStack, user: Variant, _c: InvTransferContext) -> bool:
		return user["hunger"] < 100
	func use(_s: InvItemStack, user: Variant, _c: InvTransferContext) -> StringName:
		user["hunger"] = mini(user["hunger"] + restores, 100)
		return CONSUME


class Can extends InvUsableComponent:
	var capacity: int = 3
	func _init() -> void:
		data_key = &"water"
	func init_data(s: InvItemStack) -> void:
		s.data[data_key] = capacity
	func can_merge(_a: InvItemStack, _b: InvItemStack) -> bool:
		return false
	func use(s: InvItemStack, user: Variant, _c: InvTransferContext) -> StringName:
		var w := int(s.data[data_key])
		if w <= 0:
			return FAILED
		s.data[data_key] = w - 1
		user["watered"] += 1
		return CHANGED


class Inert extends InvUsableComponent:
	pass


class LockedPolicy extends InvContainerPolicy:
	func can_remove(_c: InvContainer, _i: int, _n: int, _ctx: InvTransferContext) -> InvDropCheck:
		return InvDropCheck.reject(InvDropCheck.LOCKED)


var db: InvItemDatabase
var berry: InvItemDef
var can: InvItemDef
var wood: InvItemDef
var rock: InvItemDef


func suite_name() -> String:
	return "inv_use"


func suite_setup(_ctx: Dictionary) -> void:
	db = InvItemDatabase.new()
	berry = _def(&"berry", 20, [Food.new()])
	can = _def(&"can", 1, [Can.new()])
	wood = _def(&"wood", 50, [])
	rock = _def(&"rock", 10, [Inert.new()])


func _def(id: StringName, max_stack: int, comps: Array) -> InvItemDef:
	var d := InvItemDef.new()
	d.id = id
	d.max_stack = max_stack
	var c: Array[InvItemComponent] = []
	for x in comps:
		c.append(x)
	d.components = c
	db.register(d)
	return d


func _player() -> Dictionary:
	return {"hunger": 40, "watered": 0}


func test_find_usable() -> void:
	assert_true(InvUsableComponent.find(berry) is Food)
	assert_eq(InvUsableComponent.find(wood), null)
	assert_eq(InvUsableComponent.find(null), null)
	assert_eq((InvUsableComponent.find(berry) as InvUsableComponent).use_label, "Eat")


func test_consume_removes_one_and_applies_effect() -> void:
	var c := InvContainer.new(1)
	c.set_stack(0, InvItemStack.make(berry, 3))
	var p := _player()
	var removed := []
	c.item_removed.connect(func(d: InvItemDef, n: int) -> void: removed.append([d.id, n]))
	assert_eq(InvUsableComponent.use_slot(c, 0, p), InvUsableComponent.CONSUME)
	assert_eq(p["hunger"], 65)
	assert_eq(c.get_stack(0).count, 2)
	assert_eq(removed, [[&"berry", 1]])
	InvUsableComponent.use_slot(c, 0, p)
	assert_eq(InvUsableComponent.use_slot(c, 0, p), InvUsableComponent.CONSUME, "last one")
	assert_true(c.is_slot_empty(0))
	assert_eq(p["hunger"], 100)
	assert_eq(InvUsableComponent.use_slot(c, 0, p), InvUsableComponent.NOOP, "empty slot")


func test_can_use_gate() -> void:
	var c := InvContainer.new(1)
	c.set_stack(0, InvItemStack.make(berry, 3))
	var p := {"hunger": 100}
	assert_eq(InvUsableComponent.use_slot(c, 0, p), InvUsableComponent.NOOP)
	assert_eq(c.get_stack(0).count, 3, "not consumed when can_use is false")


func test_changed_keeps_unit_and_touches_slot() -> void:
	var c := InvContainer.new(1)
	c.set_stack(0, InvItemStack.make(can, 1))
	var p := _player()
	var changed := []
	c.slot_changed.connect(func(i: int) -> void: changed.append(i))
	var removed := [0]
	c.item_removed.connect(func(_d: InvItemDef, n: int) -> void: removed[0] += n)
	assert_eq(InvUsableComponent.use_slot(c, 0, p), InvUsableComponent.CHANGED)
	assert_eq(c.get_stack(0).data[&"water"], 2)
	assert_eq(c.get_stack(0).count, 1)
	assert_eq(changed, [0], "touch() re-emitted slot_changed")
	assert_eq(removed[0], 0, "no item delta for a data-only change")
	InvUsableComponent.use_slot(c, 0, p)
	InvUsableComponent.use_slot(c, 0, p)
	assert_eq(p["watered"], 3)
	assert_eq(InvUsableComponent.use_slot(c, 0, p), InvUsableComponent.FAILED, "empty can")
	assert_eq(c.get_stack(0).count, 1, "FAILED never consumes")


func test_noop_for_non_usable_and_inert() -> void:
	var c := InvContainer.new(2)
	c.set_stack(0, InvItemStack.make(wood, 5))
	c.set_stack(1, InvItemStack.make(rock, 2))
	assert_eq(InvUsableComponent.use_slot(c, 0, _player()), InvUsableComponent.NOOP)
	assert_eq(InvUsableComponent.use_slot(c, 1, _player()), InvUsableComponent.NOOP, "base use() is NOOP")
	assert_eq(c.get_stack(1).count, 2)
	assert_eq(InvUsableComponent.use_slot(c, 7, _player()), InvUsableComponent.NOOP)
	assert_eq(InvUsableComponent.use_slot(null, 0, _player()), InvUsableComponent.NOOP)


func test_locked_policy_blocks_before_effect() -> void:
	var c := InvContainer.new(1)
	c.policy = LockedPolicy.new()
	c.set_stack(0, InvItemStack.make(berry, 3))
	var p := _player()
	assert_eq(InvUsableComponent.use_slot(c, 0, p), InvUsableComponent.FAILED)
	assert_eq(p["hunger"], 40, "effect never applied")
	assert_eq(c.get_stack(0).count, 3)


func test_hotbar_use_active_and_signal() -> void:
	var c := InvContainer.new(3)
	c.set_stack(0, InvItemStack.make(berry, 2))
	c.set_stack(1, InvItemStack.make(can, 1))
	var hb := InvHotbar.new(c)
	var p := _player()
	var active := []
	hb.active_changed.connect(func(i: int, s: InvItemStack) -> void: active.append([i, s.count, s.data.get(&"water", -1)]))
	assert_eq(hb.use_active(p), InvUsableComponent.CONSUME)
	assert_eq(active[-1], [0, 1, -1])
	hb.select(1)
	assert_true(hb.active_usable() is Can)
	assert_eq(hb.use_active(p), InvUsableComponent.CHANGED)
	assert_eq(active[-1], [1, 1, 2], "data-only change still reaches the hotbar listener")
	hb.select(2)
	assert_eq(hb.active_usable(), null)
	assert_eq(hb.use_active(p), InvUsableComponent.NOOP)


func test_touch_active_after_manual_mutation() -> void:
	var c := InvContainer.new(1)
	c.set_stack(0, InvItemStack.make(can, 1))
	var hb := InvHotbar.new(c)
	var n := [0]
	hb.active_changed.connect(func(_i: int, _s: InvItemStack) -> void: n[0] += 1)
	hb.active_stack().data[&"water"] = 0
	hb.touch_active()
	assert_eq(n[0], 1)
	c.touch(5)  # invalid index: silent
	assert_eq(n[0], 1)


func test_water_level_survives_save() -> void:
	var c := InvContainer.new(1)
	c.set_stack(0, InvItemStack.make(can, 1))
	InvUsableComponent.use_slot(c, 0, _player())
	var save := InvSaveState.new()
	save.register(&"c", c)
	var text := save.to_json()
	var c2 := InvContainer.new(1)
	var save2 := InvSaveState.new()
	save2.register(&"c", c2)
	save2.from_json(text, db)
	assert_eq(int(c2.get_stack(0).data["water"]), 2)
