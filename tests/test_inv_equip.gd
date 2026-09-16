@tool
extends McpTestSuite

## Phase 4 headless tests: InvEquipment, InvHotbar, InvSorter, and the
## quick-move routing preferences (merge targets, then filtered storage).


class NoMergeComponent extends InvItemComponent:
	func _init() -> void:
		data_key = &"nomerge"
	func can_merge(_a: InvItemStack, _b: InvItemStack) -> bool:
		return false


class LockedPolicy extends InvContainerPolicy:
	func can_remove(_c: InvContainer, _i: int, _n: int, _ctx: InvTransferContext) -> InvDropCheck:
		return InvDropCheck.reject(InvDropCheck.LOCKED)


var db: InvItemDatabase
var wood: InvItemDef
var stone: InvItemDef
var berry: InvItemDef
var axe: InvItemDef    # hand
var hat: InvItemDef    # head
var ring: InvItemDef   # ring


func suite_name() -> String:
	return "inv_equip"


func suite_setup(_ctx: Dictionary) -> void:
	db = InvItemDatabase.new()
	wood = _def(&"wood", 50, [&"material"])
	stone = _def(&"stone", 50, [&"material"])
	berry = _def(&"berry", 20, [&"food"])
	axe = _def(&"axe", 1, [&"tool"], &"hand", [NoMergeComponent.new()])
	hat = _def(&"hat", 1, [&"armor"], &"head")
	ring = _def(&"ring", 1, [&"jewelry"], &"ring")


func _def(id: StringName, max_stack: int, tags: Array, equip: StringName = &"", comps: Array = []) -> InvItemDef:
	var d := InvItemDef.new()
	d.id = id
	d.max_stack = max_stack
	var t: Array[StringName] = []
	for x in tags:
		t.append(x)
	d.tags = t
	d.equip_type = equip
	var c: Array[InvItemComponent] = []
	for x in comps:
		c.append(x)
	d.components = c
	db.register(d)
	return d


func _c(n: int, id: StringName = &"c") -> InvContainer:
	return InvContainer.new(n, id)


func _put(c: InvContainer, i: int, def: InvItemDef, n: int) -> void:
	c.set_stack(i, InvItemStack.make(def, n))


func _ids(c: InvContainer) -> Array:
	var out := []
	for i in c.size():
		var s := c.get_stack(i)
		out.append("" if s.is_empty() else "%s:%d" % [s.def.id, s.count])
	return out


# ---------------------------------------------------------------- equipment

func test_equipment_structure() -> void:
	var e := InvEquipment.new([&"head", &"hand", &"ring", &"ring"])
	assert_eq(e.size(), 4)
	assert_eq(e.slot_for(&"head"), 0)
	assert_eq(e.slot_for(&"ring"), 2)
	assert_eq(e.slot_for(&"ring", 1), 3)
	assert_eq(e.slot_for(&"ring", 2), -1)
	assert_eq(e.slot_for(&"feet"), -1)
	assert_eq(e.type_of(1), &"hand")
	assert_eq(e.container.get_slot_max(0), 1)
	assert_true(e.accepts_def(hat))
	assert_false(e.accepts_def(wood))


func test_equip_routes_by_type_and_emits() -> void:
	var e := InvEquipment.new([&"head", &"hand"])
	var inv := _c(3)
	_put(inv, 0, hat, 1)
	_put(inv, 1, axe, 1)
	var got := []
	e.equipped.connect(func(t: StringName, d: InvItemDef) -> void: got.append([t, d.id]))
	assert_true(e.equip(inv, 1).ok)
	assert_true(e.equip(inv, 0).ok)
	assert_eq(e.get_equipped_def(&"hand"), axe)
	assert_eq(e.get_equipped_def(&"head"), hat)
	assert_true(inv.is_empty())
	assert_eq(got, [[&"hand", &"axe"], [&"head", &"hat"]])


func test_equip_rejects_non_equippable_and_wrong_slot() -> void:
	var e := InvEquipment.new([&"head"])
	var inv := _c(2)
	_put(inv, 0, wood, 5)
	_put(inv, 1, axe, 1)
	assert_eq(e.equip(inv, 0).hint, InvDropCheck.WRONG_TYPE)
	assert_eq(e.equip(inv, 1).hint, InvDropCheck.WRONG_TYPE, "no hand slot")
	# Direct transfer into the wrong slot is refused by the filter too.
	assert_eq(InvTransfer.move(inv, 1, e.container, 0).hint, InvDropCheck.WRONG_TYPE)
	assert_eq(inv.get_stack(0).count, 5)


func test_equip_swaps_when_occupied_and_prefers_empty_duplicate() -> void:
	var e := InvEquipment.new([&"ring", &"ring"])
	var gold_ring := _def(&"gold_ring", 1, [&"jewelry"], &"ring")
	var inv := _c(3)
	_put(inv, 0, ring, 1)
	_put(inv, 1, ring, 1)
	_put(inv, 2, gold_ring, 1)
	assert_eq(e.equip(inv, 0).to_index, 0)
	assert_eq(e.equip(inv, 1).to_index, 1, "second ring goes to the empty duplicate slot")
	var r := e.equip(inv, 2)
	assert_true(r.ok)
	assert_true(r.swapped, "both full: swap with the first")
	assert_eq(inv.get_stack(2).def, ring)
	assert_eq(e.get_equipped_def(&"ring", 0), gold_ring)
	assert_true(e.is_equipped(&"ring", 0))
	assert_true(e.is_equipped(&"ring", 1))


func test_unequip_and_signal() -> void:
	var e := InvEquipment.new([&"head"])
	var inv := _c(2)
	_put(inv, 0, hat, 1)
	_put(inv, 1, wood, 50)
	e.equip(inv, 0)
	var un := []
	e.unequipped.connect(func(t: StringName, d: InvItemDef) -> void: un.append([t, d.id]))
	assert_true(e.unequip(&"head", inv).ok)
	assert_eq(inv.get_stack(0).def, hat)
	assert_false(e.is_equipped(&"head"))
	assert_eq(un, [[&"head", &"hat"]])
	assert_eq(e.unequip(&"feet", inv).hint, InvDropCheck.INVALID_INDEX)


func test_equipment_via_held_stack_swap_emits_both() -> void:
	var e := InvEquipment.new([&"head"])
	var inv := _c(2)
	var hat2 := _def(&"hat2", 1, [&"armor"], &"head")
	_put(inv, 0, hat, 1)
	_put(inv, 1, hat2, 1)
	e.equip(inv, 0)
	var log := []
	e.equipped.connect(func(_t: StringName, d: InvItemDef) -> void: log.append("+" + d.id))
	e.unequipped.connect(func(_t: StringName, d: InvItemDef) -> void: log.append("-" + d.id))
	var h := InvHeldStack.new()
	h.pickup(inv, 1)
	var r := h.place(e.container, 0)
	assert_true(r.ok and r.swapped)
	assert_eq(h.def(), hat)
	assert_eq(e.get_equipped_def(&"head"), hat2)
	assert_eq(log, ["-hat", "+hat2"])


# ------------------------------------------------------------------- hotbar

func test_hotbar_selection_wraps_and_signals() -> void:
	var c := _c(4)
	var hb := InvHotbar.new(c)
	var sel := []
	hb.selection_changed.connect(func(i: int) -> void: sel.append(i))
	hb.select_next()
	hb.select_next()
	hb.select_prev()
	hb.select(3)
	hb.select_next()  # wraps to 0
	hb.select(0)      # no-op
	assert_eq(sel, [1, 2, 1, 3, 0])
	hb.wrap = false
	hb.select(99)
	assert_eq(hb.selected, 3)


func test_hotbar_active_changed_on_select_and_slot_change() -> void:
	var c := _c(3)
	_put(c, 1, wood, 5)
	var hb := InvHotbar.new(c)
	var log := []
	hb.active_changed.connect(func(i: int, s: InvItemStack) -> void: log.append([i, "" if s.is_empty() else String(s.def.id), s.count]))
	hb.select(1)
	_put(c, 1, wood, 7)     # count change on the active slot
	_put(c, 2, stone, 1)    # other slot: silent
	c.clear_slot(1)         # active emptied
	assert_eq(log, [[1, "wood", 5], [1, "wood", 7], [1, "", 0]])


func test_hotbar_consume_active_respects_policy() -> void:
	var c := _c(2)
	_put(c, 0, berry, 3)
	var hb := InvHotbar.new(c)
	assert_true(hb.consume_active(2))
	assert_eq(c.get_stack(0).count, 1)
	assert_false(hb.consume_active(2), "not enough")
	assert_true(hb.consume_active(1))
	assert_true(c.is_slot_empty(0))
	assert_false(hb.consume_active(1), "empty")
	_put(c, 0, berry, 3)
	c.policy = LockedPolicy.new()
	assert_false(hb.consume_active(1))
	assert_eq(c.get_stack(0).count, 3)


func test_hotbar_handle_input_keys_and_wheel() -> void:
	var c := _c(3)
	var hb := InvHotbar.new(c)
	var k := InputEventKey.new()
	k.keycode = KEY_3
	k.pressed = true
	assert_true(hb.handle_input(k))
	assert_eq(hb.selected, 2)
	var k9 := InputEventKey.new()
	k9.keycode = KEY_9
	k9.pressed = true
	assert_false(hb.handle_input(k9), "out-of-range digit is left to the game")
	assert_eq(hb.selected, 2)
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_DOWN
	w.pressed = true
	assert_true(hb.handle_input(w))
	assert_eq(hb.selected, 0, "wrapped")
	hb.use_wheel = false
	assert_false(hb.handle_input(w))
	var other := InputEventMouseButton.new()
	other.button_index = MOUSE_BUTTON_LEFT
	other.pressed = true
	assert_false(hb.handle_input(other))


# ------------------------------------------------------------------- sorter

func test_compact_merges_and_packs_keeping_order() -> void:
	var c := _c(6)
	_put(c, 1, wood, 30)
	_put(c, 3, stone, 5)
	_put(c, 5, wood, 30)
	assert_true(InvSorter.compact(c))
	assert_eq(_ids(c), ["wood:50", "stone:5", "wood:10", "", "", ""])


func test_sort_default_order() -> void:
	var c := _c(6)
	_put(c, 0, wood, 10)
	_put(c, 2, berry, 3)
	_put(c, 3, stone, 7)
	_put(c, 5, wood, 20)
	assert_true(InvSorter.sort(c))
	# tags: food < material; within material: stone < wood by id.
	assert_eq(_ids(c), ["berry:3", "stone:7", "wood:30", "", "", ""])


func test_sort_custom_comparator_and_component_no_merge() -> void:
	var c := _c(4)
	_put(c, 0, axe, 1)
	_put(c, 1, wood, 1)
	_put(c, 3, axe, 1)
	var by_count_desc := func(a: InvItemStack, b: InvItemStack) -> bool: return a.count > b.count if a.count != b.count else String(a.def.id) < String(b.def.id)
	assert_true(InvSorter.sort(c, null, by_count_desc))
	assert_eq(_ids(c), ["axe:1", "axe:1", "wood:1", ""], "axes never merge")


func test_sort_respects_filters_and_slot_caps() -> void:
	var c := _c(4)
	var tools_only := InvSlotFilter.new()
	tools_only.required_tags = [&"tool"]
	c.set_filter(0, tools_only)
	c.set_slot_max(1, 10)
	_put(c, 1, axe, 1)
	_put(c, 2, wood, 25)
	_put(c, 3, wood, 5)
	assert_true(InvSorter.sort(c))
	# axe is the only thing slot 0 accepts; wood 30 splits 10 (cap) + 20.
	assert_eq(_ids(c), ["axe:1", "wood:10", "wood:20", ""])


func test_sort_aborts_on_locked_and_when_nothing_fits() -> void:
	var c := _c(2)
	_put(c, 0, wood, 5)
	_put(c, 1, stone, 5)
	c.policy = LockedPolicy.new()
	assert_false(InvSorter.sort(c))
	assert_eq(_ids(c), ["wood:5", "stone:5"])
	c.policy = null
	assert_false(InvSorter.sort(_c(3)), "empty container: nothing to do")


func test_sort_restores_on_placement_failure() -> void:
	# Two slots, both wood 50 with a filter that accepts wood; merged they fit.
	# Force failure: slot caps that shrink after removal can't happen, so
	# simulate with a filter that rejects everything on re-insert via policy.
	var c := _c(2)
	_put(c, 0, wood, 50)
	_put(c, 1, stone, 50)
	var block := InvSlotFilter.new()
	block.allowed_ids = [&"nothing"]
	c.set_filter(1, block)  # stone can never go back anywhere but slot 0
	assert_false(InvSorter.sort(c))
	assert_eq(_ids(c), ["wood:50", "stone:50"], "snapshot restored")


func test_sort_emits_container_signals_consistently() -> void:
	var c := _c(3)
	_put(c, 0, wood, 10)
	_put(c, 2, wood, 10)
	var added := [0]
	var removed := [0]
	c.item_added.connect(func(_d: InvItemDef, n: int) -> void: added[0] += n)
	c.item_removed.connect(func(_d: InvItemDef, n: int) -> void: removed[0] += n)
	InvSorter.compact(c)
	assert_eq(added[0], removed[0], "net zero: nothing created or destroyed")
	assert_eq(c.count_of(&"wood"), 20)


# --------------------------------------------------------- routing prefs

func test_quick_move_prefers_merge_target_over_first_open() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var chest_a := _c(2)
	var chest_b := _c(2)
	_put(inv, 0, wood, 10)
	_put(chest_b, 0, wood, 5)
	oc.open(inv)
	oc.open(chest_a, &"external")
	oc.open(chest_b, &"external")
	var r := oc.quick_move(inv, 0)
	assert_true(r.ok)
	assert_eq(chest_b.get_stack(0).count, 15, "merged into b even though a was opened first")
	assert_true(chest_a.is_empty())


func test_quick_move_prefers_filtered_storage() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var chest := _c(2)
	var toolbox := _c(2)
	var f := InvSlotFilter.new()
	f.required_tags = [&"tool"]
	toolbox.set_all_filters(f)
	_put(inv, 0, axe, 1)
	oc.open(inv)
	oc.open(chest, &"external")
	oc.open(toolbox, &"external")
	var r := oc.quick_move(inv, 0)
	assert_true(r.ok)
	assert_eq(r.to, toolbox)
	assert_true(chest.is_empty())


func test_quick_move_merge_then_spill_to_filtered_then_plain() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var chest := _c(1)
	var bag := _c(1)  # filtered for material, already has 45 wood
	var f := InvSlotFilter.new()
	f.required_tags = [&"material"]
	bag.set_all_filters(f)
	_put(inv, 0, wood, 30)
	_put(bag, 0, wood, 45)
	oc.open(inv)
	oc.open(chest, &"external")
	oc.open(bag, &"external")
	var r := oc.quick_move(inv, 0)
	assert_true(r.ok)
	assert_eq(r.moved_count, 30)
	assert_eq(bag.get_stack(0).count, 50)
	assert_eq(chest.get_stack(0).count, 25)


func test_quick_move_to_equipment_via_group() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(2)
	var chest := _c(2)
	var e := InvEquipment.new([&"head", &"hand"])
	_put(inv, 0, axe, 1)
	_put(inv, 1, wood, 3)
	oc.open(inv)
	oc.open(chest, &"external")
	oc.open(e.container, &"equipment")
	assert_eq(oc.quick_move(inv, 0).to, e.container, "tool prefers its filtered equipment slot")
	assert_eq(oc.quick_move(inv, 1).to, chest, "wood can't be equipped")
	assert_eq(e.get_equipped_def(&"hand"), axe)
