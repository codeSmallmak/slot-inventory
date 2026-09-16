@tool
extends McpTestSuite

## Phase 1 headless tests: data layer, container rules, InvTransfer.
## No scene tree required. Run via the godot-ai test runner
## (test_run) or any harness that instantiates McpTestSuite subclasses.


# ----------------------------------------------------------- test doubles

## Component that refuses to stack (durability-style).
class NoMergeComponent extends InvItemComponent:
	func _init() -> void:
		data_key = &"nomerge"
	func can_merge(_a: InvItemStack, _b: InvItemStack) -> bool:
		return false


## Component with per-unit state that averages on merge (spoilage-style).
class FreshnessComponent extends InvItemComponent:
	func _init() -> void:
		data_key = &"fresh"
	func init_data(stack: InvItemStack) -> void:
		stack.data[data_key] = 1.0
	func merge(target: InvItemStack, incoming: InvItemStack) -> void:
		var a: float = target.data.get(data_key, 1.0)
		var b: float = incoming.data.get(data_key, 1.0)
		target.data[data_key] = (a * target.count + b * incoming.count) / float(target.count + incoming.count)


class LockedPolicy extends InvContainerPolicy:
	func can_remove(_c: InvContainer, _i: int, _n: int, _ctx: InvTransferContext) -> InvDropCheck:
		return InvDropCheck.reject(InvDropCheck.LOCKED)


class SideEffectPolicy extends InvContainerPolicy:
	var commits: int = 0
	func _init() -> void:
		has_side_effects = true
	func can_insert(_c: InvContainer, _i: int, _s: InvItemStack, _ctx: InvTransferContext) -> InvDropCheck:
		return InvDropCheck.accept(InvDropCheck.SELL)
	func on_commit(_c: InvContainer, _role: StringName, _r: InvTransferResult, _ctx: InvTransferContext) -> void:
		commits += 1


# ------------------------------------------------------------------ fixture

var db: InvItemDatabase
var wood: InvItemDef      # stackable 50
var stone: InvItemDef     # stackable 50
var axe: InvItemDef       # max 1, no-merge component, tool tag, equip hand
var berry: InvItemDef     # stackable 20, freshness component, food tag


func suite_name() -> String:
	return "inv_core"


func suite_setup(_ctx: Dictionary) -> void:
	db = InvItemDatabase.new()
	wood = _def(&"wood", 50, [&"material", &"sellable"])
	stone = _def(&"stone", 50, [&"material"])
	axe = _def(&"axe", 1, [&"tool"], &"hand", [NoMergeComponent.new()])
	berry = _def(&"berry", 20, [&"food", &"sellable"], &"", [FreshnessComponent.new()])


func _def(id: StringName, max_stack: int, tags: Array, equip: StringName = &"", comps: Array = []) -> InvItemDef:
	var d := InvItemDef.new()
	d.id = id
	d.display_name = String(id).capitalize()
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


# ---------------------------------------------------------------- M1: data

func test_make_stack_initialises_components() -> void:
	var s := InvItemStack.make(berry, 5)
	assert_false(s.is_empty())
	assert_eq(s.count, 5)
	assert_eq(s.data.get(&"fresh"), 1.0)


func test_empty_stack_semantics() -> void:
	var s := InvItemStack.new()
	assert_true(s.is_empty())
	assert_true(InvItemStack.make(wood, 0).is_empty())
	assert_true(InvItemStack.make(null, 3).is_empty())


func test_can_merge_rules() -> void:
	assert_true(InvItemStack.make(wood, 1).can_merge_with(InvItemStack.make(wood, 1)))
	assert_false(InvItemStack.make(wood, 1).can_merge_with(InvItemStack.make(stone, 1)))
	assert_false(InvItemStack.make(axe, 1).can_merge_with(InvItemStack.make(axe, 1)), "component vetoes merge")
	assert_false(InvItemStack.make(wood, 1).can_merge_with(InvItemStack.new()), "empty never merges")


func test_database_lookup() -> void:
	assert_eq(db.get_def(&"wood"), wood)
	assert_eq(db.get_def(&"nope"), null)
	assert_true(db.has(&"axe"))
	assert_eq(db.make_stack(&"stone", 3).count, 3)


# ----------------------------------------------------- M2: container rules

func test_slots_are_never_null() -> void:
	var c := _c(4)
	for i in 4:
		assert_true(c.get_stack(i) != null)
		assert_true(c.is_slot_empty(i))


func test_effective_max_uses_slot_override() -> void:
	var c := _c(2)
	c.set_slot_max(1, 10)
	assert_eq(c.effective_max(0, wood), 50)
	assert_eq(c.effective_max(1, wood), 10)
	assert_eq(c.effective_max(1, axe), 1, "override never raises def.max_stack")


func test_filter_wrong_type() -> void:
	var c := _c(1)
	var f := InvSlotFilter.new()
	f.required_tags = [&"tool"]
	c.set_filter(0, f)
	assert_false(c.check_insert(0, InvItemStack.make(wood, 1)).ok)
	assert_eq(c.check_insert(0, InvItemStack.make(wood, 1)).hint, InvDropCheck.WRONG_TYPE)
	assert_true(c.check_insert(0, InvItemStack.make(axe, 1)).ok)


func test_filter_equip_type() -> void:
	var f := InvSlotFilter.new()
	f.equip_type = &"hand"
	assert_true(f.accepts(InvItemStack.make(axe, 1)).ok)
	assert_false(f.accepts(InvItemStack.make(wood, 1)).ok)
	assert_true(f.accepts(InvItemStack.new()).ok, "empty always passes")


func test_check_insert_hints_and_capacity() -> void:
	var c := _c(3)
	c.set_stack(1, InvItemStack.make(wood, 45))
	c.set_stack(2, InvItemStack.make(stone, 5))
	var probe := InvItemStack.make(wood, 10)
	var a := c.check_insert(0, probe)
	assert_eq(a.hint, InvDropCheck.PLACE)
	assert_eq(a.capacity, 10)
	var b := c.check_insert(1, probe)
	assert_eq(b.hint, InvDropCheck.MERGE)
	assert_eq(b.capacity, 5)
	var s := c.check_insert(2, probe)
	assert_eq(s.hint, InvDropCheck.SWAP)
	c.set_stack(1, InvItemStack.make(wood, 50))
	assert_eq(c.check_insert(1, probe).hint, InvDropCheck.FULL)


func test_count_of_and_find() -> void:
	var c := _c(4)
	c.set_stack(0, InvItemStack.make(wood, 10))
	c.set_stack(2, InvItemStack.make(wood, 7))
	c.set_stack(3, InvItemStack.make(stone, 1))
	assert_eq(c.count_of(&"wood"), 17)
	assert_eq(c.find(&"wood"), 0)
	assert_eq(c.find(&"wood", 1), 2)
	assert_eq(c.first_empty(), 1)


# ------------------------------------------------------------- M3: transfer

func test_move_into_empty_full() -> void:
	var a := _c(1, &"a")
	var b := _c(1, &"b")
	a.set_stack(0, InvItemStack.make(wood, 10))
	var r := InvTransfer.move(a, 0, b, 0)
	assert_true(r.ok)
	assert_eq(r.hint, InvDropCheck.PLACE)
	assert_eq(r.moved_count, 10)
	assert_eq(r.remainder, 0)
	assert_true(a.get_stack(0).is_empty())
	assert_eq(b.get_stack(0).count, 10)


func test_move_into_empty_partial() -> void:
	var a := _c(1)
	var b := _c(1)
	a.set_stack(0, InvItemStack.make(wood, 10))
	var r := InvTransfer.move(a, 0, b, 0, 4)
	assert_true(r.ok)
	assert_eq(r.moved_count, 4)
	assert_eq(a.get_stack(0).count, 6)
	assert_eq(b.get_stack(0).count, 4)


func test_move_capped_by_slot_max_leaves_remainder() -> void:
	var a := _c(1)
	var b := _c(1)
	b.set_slot_max(0, 3)
	a.set_stack(0, InvItemStack.make(wood, 10))
	var r := InvTransfer.move(a, 0, b, 0)
	assert_true(r.ok)
	assert_eq(r.moved_count, 3)
	assert_eq(r.remainder, 7)
	assert_eq(a.get_stack(0).count, 7)


func test_merge_with_remainder_in_source() -> void:
	var a := _c(1)
	var b := _c(1)
	a.set_stack(0, InvItemStack.make(wood, 30))
	b.set_stack(0, InvItemStack.make(wood, 40))
	var r := InvTransfer.move(a, 0, b, 0)
	assert_true(r.ok)
	assert_eq(r.hint, InvDropCheck.MERGE)
	assert_eq(r.moved_count, 10)
	assert_eq(r.remainder, 20)
	assert_eq(b.get_stack(0).count, 50)
	assert_eq(a.get_stack(0).count, 20)


func test_merge_into_full_fails_no_change() -> void:
	var a := _c(1)
	var b := _c(1)
	a.set_stack(0, InvItemStack.make(wood, 5))
	b.set_stack(0, InvItemStack.make(wood, 50))
	var r := InvTransfer.move(a, 0, b, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.FULL)
	assert_eq(a.get_stack(0).count, 5)
	assert_eq(b.get_stack(0).count, 50)


func test_merge_blocked_by_component_becomes_swap() -> void:
	var a := _c(1)
	var b := _c(1)
	var ax1 := InvItemStack.make(axe, 1)
	ax1.data[&"nomerge"] = 0.5
	var ax2 := InvItemStack.make(axe, 1)
	ax2.data[&"nomerge"] = 0.9
	a.set_stack(0, ax1)
	b.set_stack(0, ax2)
	var r := InvTransfer.move(a, 0, b, 0)
	assert_true(r.ok)
	assert_true(r.swapped)
	assert_eq(a.get_stack(0).data[&"nomerge"], 0.9)
	assert_eq(b.get_stack(0).data[&"nomerge"], 0.5)


func test_swap_different_items() -> void:
	var a := _c(1)
	var b := _c(1)
	a.set_stack(0, InvItemStack.make(wood, 10))
	b.set_stack(0, InvItemStack.make(stone, 20))
	var r := InvTransfer.move(a, 0, b, 0)
	assert_true(r.ok)
	assert_eq(r.hint, InvDropCheck.SWAP)
	assert_true(r.swapped)
	assert_eq(r.moved_count, 10)
	assert_eq(r.swapped_def, stone)
	assert_eq(r.swapped_count, 20)
	assert_eq(a.get_stack(0).def, stone)
	assert_eq(a.get_stack(0).count, 20)
	assert_eq(b.get_stack(0).def, wood)
	assert_eq(b.get_stack(0).count, 10)


func test_partial_swap_is_blocked() -> void:
	var a := _c(1)
	var b := _c(1)
	a.set_stack(0, InvItemStack.make(wood, 10))
	b.set_stack(0, InvItemStack.make(stone, 20))
	var r := InvTransfer.move(a, 0, b, 0, 5)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.SWAP_BLOCKED)
	assert_eq(a.get_stack(0).count, 10)
	assert_eq(b.get_stack(0).count, 20)


func test_swap_rejected_when_source_refuses_incoming() -> void:
	var a := _c(1)
	var f := InvSlotFilter.new()
	f.required_tags = [&"material"]
	a.set_filter(0, f)
	var b := _c(1)
	a.set_stack(0, InvItemStack.make(wood, 10))
	b.set_stack(0, InvItemStack.make(axe, 1))   # not a material
	var r := InvTransfer.move(a, 0, b, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.WRONG_TYPE)
	assert_eq(a.get_stack(0).def, wood)
	assert_eq(b.get_stack(0).def, axe)


func test_swap_rejected_when_swapped_out_stack_too_big_for_source() -> void:
	var a := _c(1)
	a.set_slot_max(0, 5)
	var b := _c(1)
	a.set_stack(0, InvItemStack.make(wood, 5))
	b.set_stack(0, InvItemStack.make(stone, 20))
	var r := InvTransfer.move(a, 0, b, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.FULL)
	assert_eq(a.get_stack(0).count, 5)


func test_split_half_odd_stack() -> void:
	var a := _c(1)
	var held := _c(1, &"held")
	a.set_stack(0, InvItemStack.make(wood, 7))
	var r := InvTransfer.move_half(a, 0, held, 0)
	assert_true(r.ok)
	assert_eq(held.get_stack(0).count, 4)
	assert_eq(a.get_stack(0).count, 3)


func test_place_one_repeatedly_until_empty() -> void:
	var held := _c(1, &"held")
	var bag := _c(3)
	held.set_stack(0, InvItemStack.make(wood, 3))
	for i in 3:
		var r := InvTransfer.move_one(held, 0, bag, i)
		assert_true(r.ok)
		assert_eq(bag.get_stack(i).count, 1)
	assert_true(held.get_stack(0).is_empty())
	var r2 := InvTransfer.move_one(held, 0, bag, 0)
	assert_false(r2.ok)
	assert_eq(r2.hint, InvDropCheck.EMPTY)


func test_same_slot_is_noop() -> void:
	var a := _c(1)
	a.set_stack(0, InvItemStack.make(wood, 3))
	var r := InvTransfer.move(a, 0, a, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.NOOP)


func test_move_within_same_container() -> void:
	var a := _c(2)
	a.set_stack(0, InvItemStack.make(wood, 3))
	var r := InvTransfer.move(a, 0, a, 1)
	assert_true(r.ok)
	assert_true(a.get_stack(0).is_empty())
	assert_eq(a.get_stack(1).count, 3)


func test_component_merge_averages_state() -> void:
	var a := _c(1)
	var b := _c(1)
	var fresh := InvItemStack.make(berry, 10)     # freshness 1.0
	var stale := InvItemStack.make(berry, 10)
	stale.data[&"fresh"] = 0.5
	a.set_stack(0, stale)
	b.set_stack(0, fresh)
	var r := InvTransfer.move(a, 0, b, 0)
	assert_true(r.ok)
	assert_eq(b.get_stack(0).count, 20)
	assert_true(is_equal_approx(b.get_stack(0).data[&"fresh"], 0.75))


func test_component_split_copies_state() -> void:
	var a := _c(1)
	var b := _c(1)
	var s := InvItemStack.make(berry, 10)
	s.data[&"fresh"] = 0.3
	a.set_stack(0, s)
	InvTransfer.move(a, 0, b, 0, 4)
	assert_true(is_equal_approx(a.get_stack(0).data[&"fresh"], 0.3))
	assert_true(is_equal_approx(b.get_stack(0).data[&"fresh"], 0.3))


# ---------------------------------------------------------------- policies

func test_locked_policy_blocks_removal() -> void:
	var chest := _c(1)
	chest.policy = LockedPolicy.new()
	var bag := _c(1)
	chest.set_stack(0, InvItemStack.make(wood, 5))
	var r := InvTransfer.move(chest, 0, bag, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.LOCKED)
	assert_eq(chest.get_stack(0).count, 5)
	# Inserting into a locked chest is still fine (only removal is locked).
	bag.set_stack(0, InvItemStack.make(stone, 5))
	var r2 := InvTransfer.move(bag, 0, chest, 0)
	assert_false(r2.ok, "would be a swap, and swap needs removal from chest")
	assert_eq(r2.hint, InvDropCheck.LOCKED)


func test_policy_hint_propagates_and_on_commit_fires() -> void:
	var sell := _c(1)
	var pol := SideEffectPolicy.new()
	sell.policy = pol
	var bag := _c(1)
	bag.set_stack(0, InvItemStack.make(wood, 5))
	var r := InvTransfer.move(bag, 0, sell, 0, 2)
	assert_true(r.ok)
	assert_eq(r.hint, InvDropCheck.SELL)
	assert_eq(r.moved_count, 2)
	assert_eq(pol.commits, 1)


func test_swap_blocked_by_side_effect_policy() -> void:
	var sell := _c(1)
	sell.policy = SideEffectPolicy.new()
	var bag := _c(1)
	bag.set_stack(0, InvItemStack.make(wood, 5))
	sell.set_stack(0, InvItemStack.make(stone, 5))
	var r := InvTransfer.move(bag, 0, sell, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.SWAP_BLOCKED)
	assert_eq(bag.get_stack(0).def, wood)
	assert_eq(sell.get_stack(0).def, stone)


# ---------------------------------------------------------------- bulk ops

func test_consume_is_atomic_across_slots() -> void:
	var c := _c(4)
	c.set_stack(0, InvItemStack.make(wood, 3))
	c.set_stack(2, InvItemStack.make(wood, 4))
	assert_false(c.consume(&"wood", 8), "not enough -> refuse")
	assert_eq(c.count_of(&"wood"), 7, "nothing consumed on refusal")
	assert_true(c.consume(&"wood", 5))
	assert_eq(c.count_of(&"wood"), 2)
	assert_true(c.get_stack(0).is_empty())
	assert_eq(c.get_stack(2).count, 2)


func test_consume_respects_locked_policy() -> void:
	var c := _c(1)
	c.policy = LockedPolicy.new()
	c.set_stack(0, InvItemStack.make(wood, 3))
	assert_false(c.consume(&"wood", 1))
	assert_eq(c.count_of(&"wood"), 3)


func test_add_auto_merges_first_then_fills_empty() -> void:
	var c := _c(3)
	c.set_stack(1, InvItemStack.make(wood, 45))
	var rem := c.add_auto(InvItemStack.make(wood, 60))
	assert_eq(c.get_stack(1).count, 50, "topped up existing stack first")
	assert_eq(c.get_stack(0).count, 50, "then first empty slot")
	assert_eq(c.get_stack(2).count, 5)
	assert_true(rem.is_empty())


func test_add_auto_returns_remainder_when_full() -> void:
	var c := _c(1)
	var rem := c.add_auto(InvItemStack.make(wood, 70))
	assert_eq(c.get_stack(0).count, 50)
	assert_eq(rem.count, 20)


func test_add_auto_all_or_nothing() -> void:
	var c := _c(1)
	var s := InvItemStack.make(wood, 70)
	var rem := c.add_auto(s, null, true)
	assert_eq(rem.count, 70)
	assert_true(c.get_stack(0).is_empty())


func test_add_auto_respects_filters() -> void:
	var c := _c(2)
	var f := InvSlotFilter.new()
	f.required_tags = [&"tool"]
	c.set_filter(0, f)
	c.add_auto(InvItemStack.make(wood, 5))
	assert_true(c.get_stack(0).is_empty())
	assert_eq(c.get_stack(1).count, 5)


func test_move_auto_spreads_across_target() -> void:
	var a := _c(1)
	var b := _c(3)
	b.set_slot_max(0, 10)
	b.set_stack(1, InvItemStack.make(wood, 48))
	a.set_stack(0, InvItemStack.make(wood, 30))
	var r := InvTransfer.move_auto(a, 0, b)
	assert_true(r.ok)
	assert_eq(r.moved_count, 30)
	assert_eq(r.remainder, 0)
	assert_eq(b.get_stack(1).count, 50, "merge pass first")
	assert_eq(b.get_stack(0).count, 10, "then empty slots, capped")
	assert_eq(b.get_stack(2).count, 18)
	assert_true(a.get_stack(0).is_empty())


# ------------------------------------------------------------------ signals

var _added: Array = []
var _removed: Array = []
var _changed: Array = []
var _committed: int = 0


func setup() -> void:
	_added.clear()
	_removed.clear()
	_changed.clear()
	_committed = 0


func _wire(c: InvContainer) -> void:
	c.item_added.connect(func(d: InvItemDef, n: int) -> void: _added.append([d.id, n]))
	c.item_removed.connect(func(d: InvItemDef, n: int) -> void: _removed.append([d.id, n]))
	c.slot_changed.connect(func(i: int) -> void: _changed.append(i))
	c.transaction_committed.connect(func(_r: InvTransferResult) -> void: _committed += 1)


func test_signals_on_move_and_merge() -> void:
	var a := _c(1)
	var b := _c(1)
	_wire(a)
	_wire(b)
	a.set_stack(0, InvItemStack.make(wood, 10))
	assert_eq(_added, [[&"wood", 10]])
	assert_eq(_changed, [0])
	InvTransfer.move(a, 0, b, 0, 4)
	assert_eq(_removed, [[&"wood", 4]])
	assert_eq(_added, [[&"wood", 10], [&"wood", 4]])
	assert_eq(_committed, 2, "both containers see the commit")


func test_signals_on_swap() -> void:
	var a := _c(1)
	_wire(a)
	a.set_stack(0, InvItemStack.make(wood, 10))
	var b := _c(1)
	b.set_stack(0, InvItemStack.make(stone, 3))
	setup()
	InvTransfer.move(a, 0, b, 0)
	assert_eq(_removed, [[&"wood", 10]])
	assert_eq(_added, [[&"stone", 3]])
	assert_eq(_committed, 1)


func test_no_signals_on_failed_transfer() -> void:
	var a := _c(1)
	var b := _c(1)
	_wire(a)
	_wire(b)
	a.set_stack(0, InvItemStack.make(wood, 5))
	b.set_stack(0, InvItemStack.make(wood, 50))
	setup()
	var r := InvTransfer.move(a, 0, b, 0)
	assert_false(r.ok)
	assert_eq(_changed.size(), 0)
	assert_eq(_committed, 0)


# ------------------------------------------------------------ serialisation

func test_to_array_from_array_round_trip() -> void:
	var a := _c(3, &"bag")
	a.set_stack(0, InvItemStack.make(wood, 12))
	var s := InvItemStack.make(berry, 4)
	s.data[&"fresh"] = 0.42
	a.set_stack(2, s)
	var arr := a.to_array()
	assert_eq(arr.size(), 3)
	assert_eq(arr[1], {})
	# Survive a JSON hop, as a real save would.
	var json := JSON.stringify(arr)
	var back: Variant = JSON.parse_string(json)
	assert_true(back is Array)
	var b := _c(3, &"bag")
	b.from_array(back, db)
	assert_eq(b.get_stack(0).def, wood)
	assert_eq(b.get_stack(0).count, 12)
	assert_true(b.get_stack(1).is_empty())
	assert_eq(b.get_stack(2).def, berry)
	assert_eq(b.get_stack(2).count, 4)
	assert_true(is_equal_approx(b.get_stack(2).data.get("fresh", 0.0), 0.42))


func test_from_array_unknown_id_becomes_empty() -> void:
	var b := _c(1)
	b.from_array([{"id": "ghost", "count": 3, "data": {}}], db)
	assert_true(b.get_stack(0).is_empty())
