@tool
extends McpTestSuite

## Phase 2 headless tests: InvHeldStack (cursor), InvOpenContext
## (open containers + routing), quick-move, collect.


class NoMergeComponent extends InvItemComponent:
	func _init() -> void:
		data_key = &"nomerge"
	func can_merge(_a: InvItemStack, _b: InvItemStack) -> bool:
		return false


class LockedPolicy extends InvContainerPolicy:
	func can_remove(_c: InvContainer, _i: int, _n: int, _ctx: InvTransferContext) -> InvDropCheck:
		return InvDropCheck.reject(InvDropCheck.LOCKED)


var db: InvItemDatabase
var wood: InvItemDef   # 50
var stone: InvItemDef  # 50
var axe: InvItemDef    # 1, no-merge


func suite_name() -> String:
	return "inv_held"


func suite_setup(_ctx: Dictionary) -> void:
	db = InvItemDatabase.new()
	wood = _def(&"wood", 50, [&"material"])
	stone = _def(&"stone", 50, [&"material"])
	axe = _def(&"axe", 1, [&"tool"], [NoMergeComponent.new()])


func _def(id: StringName, max_stack: int, tags: Array, comps: Array = []) -> InvItemDef:
	var d := InvItemDef.new()
	d.id = id
	d.max_stack = max_stack
	var t: Array[StringName] = []
	for x in tags:
		t.append(x)
	d.tags = t
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


# ------------------------------------------------------------- held: pickup

func test_pickup_whole_records_origin() -> void:
	var c := _c(3)
	_put(c, 1, wood, 10)
	var h := InvHeldStack.new()
	assert_false(h.is_holding())
	var r := h.pickup(c, 1)
	assert_true(r.ok)
	assert_true(h.is_holding())
	assert_eq(h.count(), 10)
	assert_true(c.is_slot_empty(1))
	assert_eq(h.origin_container, c)
	assert_eq(h.origin_index, 1)


func test_pickup_half_rounds_up() -> void:
	var c := _c(1)
	_put(c, 0, wood, 7)
	var h := InvHeldStack.new()
	assert_true(h.pickup_half(c, 0).ok)
	assert_eq(h.count(), 4)
	assert_eq(c.get_stack(0).count, 3)


func test_pickup_same_item_merges_into_hand() -> void:
	var c := _c(2)
	_put(c, 0, wood, 10)
	_put(c, 1, wood, 45)
	var h := InvHeldStack.new()
	h.pickup(c, 0)
	var r := h.pickup(c, 1)
	assert_true(r.ok)
	assert_eq(r.hint, InvDropCheck.MERGE)
	assert_eq(h.count(), 50, "capped at max_stack")
	assert_eq(c.get_stack(1).count, 5, "remainder stays in slot")
	assert_eq(h.origin_index, 0, "origin is the FIRST pickup")


func test_pickup_other_item_swaps() -> void:
	var c := _c(2)
	_put(c, 0, wood, 10)
	_put(c, 1, stone, 3)
	var h := InvHeldStack.new()
	h.pickup(c, 0)
	var r := h.pickup(c, 1)
	assert_true(r.ok)
	assert_true(r.swapped)
	assert_eq(h.def(), stone)
	assert_eq(h.count(), 3)
	assert_eq(c.get_stack(1).def, wood)
	assert_eq(c.get_stack(1).count, 10)


func test_pickup_from_locked_fails_and_hand_stays_empty() -> void:
	var c := _c(1)
	c.policy = LockedPolicy.new()
	_put(c, 0, wood, 10)
	var h := InvHeldStack.new()
	var r := h.pickup(c, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.LOCKED)
	assert_false(h.is_holding())
	assert_eq(h.origin_container, null)


# -------------------------------------------------------------- held: place

func test_place_all_into_empty_clears_origin() -> void:
	var a := _c(1)
	var b := _c(1)
	_put(a, 0, wood, 10)
	var h := InvHeldStack.new()
	h.pickup(a, 0)
	var r := h.place(b, 0)
	assert_true(r.ok)
	assert_false(h.is_holding())
	assert_eq(b.get_stack(0).count, 10)
	assert_eq(h.origin_container, null)


func test_place_one_keeps_rest_held() -> void:
	var a := _c(1)
	var b := _c(1)
	_put(a, 0, wood, 10)
	var h := InvHeldStack.new()
	h.pickup(a, 0)
	assert_true(h.place_one(b, 0).ok)
	assert_eq(h.count(), 9)
	assert_eq(b.get_stack(0).count, 1)
	assert_eq(h.origin_container, a, "origin kept while still holding")


func test_failed_place_stays_held() -> void:
	var a := _c(1)
	var b := _c(1)
	_put(a, 0, wood, 10)
	_put(b, 0, stone, 50)
	b.set_all_slot_max(50)
	var f := InvSlotFilter.new()
	f.required_tags = [&"tool"]
	b.set_filter(0, f)
	var h := InvHeldStack.new()
	h.pickup(a, 0)
	var r := h.place(b, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.WRONG_TYPE)
	assert_eq(h.count(), 10)
	assert_eq(b.get_stack(0).count, 50)


func test_place_onto_other_item_swaps() -> void:
	var a := _c(1)
	var b := _c(1)
	_put(a, 0, wood, 10)
	_put(b, 0, axe, 1)
	var h := InvHeldStack.new()
	h.pickup(a, 0)
	var r := h.place(b, 0)
	assert_true(r.ok)
	assert_true(r.swapped)
	assert_eq(h.def(), axe)
	assert_eq(b.get_stack(0).def, wood)


func test_place_partial_onto_other_item_is_blocked() -> void:
	var a := _c(1)
	var b := _c(1)
	_put(a, 0, wood, 10)
	_put(b, 0, stone, 1)
	var h := InvHeldStack.new()
	h.pickup(a, 0)
	var r := h.place_one(b, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.SWAP_BLOCKED)
	assert_eq(h.count(), 10)


func test_place_auto_merges_then_fills() -> void:
	var a := _c(1)
	var b := _c(3)
	_put(a, 0, wood, 30)
	_put(b, 1, wood, 40)
	var h := InvHeldStack.new()
	h.pickup(a, 0)
	var r := h.place_auto(b)
	assert_true(r.ok)
	assert_false(h.is_holding())
	assert_eq(b.get_stack(1).count, 50)
	assert_eq(b.get_stack(0).count, 20)


func test_place_when_empty_hand_fails() -> void:
	var h := InvHeldStack.new()
	var r := h.place(_c(1), 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.EMPTY)


func test_preview_reports_hint_without_mutating() -> void:
	var a := _c(1)
	var b := _c(2)
	_put(a, 0, wood, 10)
	_put(b, 1, stone, 1)
	var h := InvHeldStack.new()
	h.pickup(a, 0)
	assert_eq(h.preview(b, 0).hint, InvDropCheck.PLACE)
	assert_eq(h.preview(b, 1).hint, InvDropCheck.SWAP)
	assert_eq(h.count(), 10)
	assert_true(b.is_slot_empty(0))


# -------------------------------------------------------- held: return/take

func test_return_home_prefers_origin_slot() -> void:
	var c := _c(2)
	_put(c, 1, wood, 10)
	var h := InvHeldStack.new()
	h.pickup(c, 1)
	assert_eq(h.return_home(), 0)
	assert_eq(c.get_stack(1).count, 10)
	assert_true(c.is_slot_empty(0))
	assert_false(h.is_holding())


func test_return_home_falls_back_to_other_slot() -> void:
	var c := _c(2)
	_put(c, 1, wood, 10)
	var h := InvHeldStack.new()
	h.pickup(c, 1)
	_put(c, 1, axe, 1)  # something moved in behind it
	assert_eq(h.return_home(), 0)
	assert_eq(c.get_stack(0).def, wood)
	assert_eq(c.get_stack(1).def, axe)


func test_return_home_reports_leftover_and_fallbacks() -> void:
	var c := _c(1)
	var bag := _c(1)
	_put(c, 0, wood, 10)
	var h := InvHeldStack.new()
	h.pickup(c, 0)
	_put(c, 0, stone, 50)  # origin now full of something else, no other slot
	assert_eq(h.return_home(), 10, "nothing fit back")
	assert_true(h.is_holding())
	assert_eq(h.return_home_or([bag]), 0)
	assert_eq(bag.get_stack(0).count, 10)


func test_take_hands_off_and_clears() -> void:
	var c := _c(1)
	_put(c, 0, wood, 10)
	var h := InvHeldStack.new()
	h.pickup(c, 0)
	var removed := []
	h.container().item_removed.connect(func(d: InvItemDef, n: int) -> void: removed.append([d, n]))
	var s := h.take()
	assert_eq(s.count, 10)
	assert_eq(s.def, wood)
	assert_false(h.is_holding())
	assert_eq(h.origin_container, null)
	assert_eq(removed.size(), 1)


func test_changed_signal_fires_on_pickup_and_place() -> void:
	var c := _c(2)
	_put(c, 0, wood, 10)
	var h := InvHeldStack.new()
	var n := [0]
	h.changed.connect(func() -> void: n[0] += 1)
	h.pickup(c, 0)
	h.place(c, 1)
	assert_eq(n[0], 2)


# --------------------------------------------------------------- collect

func test_collect_gathers_mergeable_up_to_max() -> void:
	var inv := _c(4)
	var chest := _c(2)
	_put(inv, 0, wood, 10)
	_put(inv, 1, stone, 5)
	_put(inv, 2, wood, 15)
	_put(chest, 0, wood, 30)
	_put(chest, 1, wood, 8)
	var h := InvHeldStack.new()
	h.pickup(inv, 0)
	var got := h.collect([inv, chest])
	assert_eq(got, 40)
	assert_eq(h.count(), 50)
	assert_true(inv.is_slot_empty(2))
	assert_eq(inv.get_stack(1).count, 5, "stone untouched")
	assert_eq(chest.get_stack(0).count, 5, "only 25 of 30 fit")
	assert_eq(chest.get_stack(1).count, 8, "hand full, untouched")


func test_collect_skips_non_mergeable_and_empty_hand() -> void:
	var inv := _c(2)
	_put(inv, 0, axe, 1)
	_put(inv, 1, axe, 1)
	var h := InvHeldStack.new()
	assert_eq(h.collect([inv]), 0, "empty hand collects nothing")
	h.pickup(inv, 0)
	assert_eq(h.collect([inv]), 0, "no-merge component blocks")
	assert_eq(inv.get_stack(1).count, 1)


func test_collect_respects_locked_source() -> void:
	var inv := _c(1)
	var locked := _c(1)
	locked.policy = LockedPolicy.new()
	_put(inv, 0, wood, 10)
	_put(locked, 0, wood, 10)
	var h := InvHeldStack.new()
	h.pickup(inv, 0)
	assert_eq(h.collect([locked]), 0)
	assert_eq(locked.get_stack(0).count, 10)


# ---------------------------------------------------------- open context

func test_open_close_tracking() -> void:
	var oc := InvOpenContext.new()
	var a := _c(1, &"a")
	var b := _c(1, &"b")
	var opened := []
	var closed := []
	oc.container_opened.connect(func(c: InvContainer, g: StringName) -> void: opened.append([c, g]))
	oc.container_closed.connect(func(c: InvContainer, g: StringName) -> void: closed.append([c, g]))
	oc.open(a)
	oc.open(b, &"external")
	oc.open(a)  # idempotent
	assert_eq(oc.size(), 2)
	assert_true(oc.is_open(a))
	assert_eq(oc.group_of(a), &"player")
	assert_eq(oc.group_of(b), &"external")
	assert_eq(opened.size(), 2)
	oc.close(b)
	assert_false(oc.is_open(b))
	assert_eq(closed.size(), 1)
	assert_eq(closed[0][1], &"external")
	oc.close(b)  # no-op
	assert_eq(closed.size(), 1)


func test_close_group() -> void:
	var oc := InvOpenContext.new()
	var a := _c(1)
	var b := _c(1)
	var d := _c(1)
	oc.open(a)
	oc.open(b, &"external")
	oc.open(d, &"external")
	oc.close_group(&"external")
	assert_eq(oc.size(), 1)
	assert_true(oc.is_open(a))


func test_targets_prefer_other_groups_in_open_order() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var hotbar := _c(1)
	var chest := _c(1)
	var chest2 := _c(1)
	oc.open(inv)
	oc.open(hotbar)
	oc.open(chest, &"external")
	oc.open(chest2, &"external")
	var t := oc.quick_move_targets(inv)
	assert_eq(t.size(), 2)
	assert_eq(t[0], chest)
	assert_eq(t[1], chest2)
	var back := oc.quick_move_targets(chest)
	assert_eq(back.size(), 2)
	assert_eq(back[0], inv)
	assert_eq(back[1], hotbar)


func test_targets_fall_back_to_same_group() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var hotbar := _c(1)
	oc.open(inv)
	oc.open(hotbar)
	var t := oc.quick_move_targets(inv)
	assert_eq(t.size(), 1)
	assert_eq(t[0], hotbar)
	assert_eq(oc.quick_move_targets(hotbar)[0], inv)


func test_explicit_route_overrides_default() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var equip := _c(1)
	var chest := _c(1)
	oc.open(inv)
	oc.open(equip, &"equipment")
	oc.open(chest, &"external")
	oc.set_route(&"player", [&"external"])
	var t := oc.quick_move_targets(inv)
	assert_eq(t.size(), 1)
	assert_eq(t[0], chest)
	oc.clear_route(&"player")
	assert_eq(oc.quick_move_targets(inv).size(), 2)


func test_targets_for_unopened_container() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var stray := _c(1)
	oc.open(inv)
	var t := oc.quick_move_targets(stray)
	assert_eq(t.size(), 1, "unopened source routes to all open containers")
	assert_eq(t[0], inv)


# -------------------------------------------------------------- quick move

func test_quick_move_merges_first_then_fills() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var chest := _c(3)
	_put(inv, 0, wood, 30)
	_put(chest, 2, wood, 45)
	oc.open(inv)
	oc.open(chest, &"external")
	var r := oc.quick_move(inv, 0)
	assert_true(r.ok)
	assert_eq(r.moved_count, 30)
	assert_eq(r.remainder, 0)
	assert_eq(r.to, chest)
	assert_true(inv.is_slot_empty(0))
	assert_eq(chest.get_stack(2).count, 50)
	assert_eq(chest.get_stack(0).count, 25)


func test_quick_move_spills_across_targets() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var chest := _c(1)
	var chest2 := _c(1)
	_put(inv, 0, wood, 30)
	_put(chest, 0, wood, 40)
	oc.open(inv)
	oc.open(chest, &"external")
	oc.open(chest2, &"external")
	var r := oc.quick_move(inv, 0)
	assert_true(r.ok)
	assert_eq(r.moved_count, 30)
	assert_eq(chest.get_stack(0).count, 50)
	assert_eq(chest2.get_stack(0).count, 20)
	assert_eq(r.to, chest2)


func test_quick_move_partial_leaves_remainder() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var chest := _c(1)
	_put(inv, 0, wood, 30)
	_put(chest, 0, wood, 45)
	oc.open(inv)
	oc.open(chest, &"external")
	var r := oc.quick_move(inv, 0)
	assert_true(r.ok)
	assert_eq(r.moved_count, 5)
	assert_eq(r.remainder, 25)
	assert_eq(inv.get_stack(0).count, 25)


func test_quick_move_amount_limits() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var chest := _c(1)
	_put(inv, 0, wood, 30)
	oc.open(inv)
	oc.open(chest, &"external")
	var r := oc.quick_move(inv, 0, 1)
	assert_true(r.ok)
	assert_eq(r.moved_count, 1)
	assert_eq(inv.get_stack(0).count, 29)


func test_quick_move_fails_cleanly_when_nowhere_fits() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var chest := _c(1)
	_put(inv, 0, wood, 30)
	_put(chest, 0, stone, 1)
	oc.open(inv)
	oc.open(chest, &"external")
	var r := oc.quick_move(inv, 0)
	assert_false(r.ok)
	assert_eq(r.moved_count, 0)
	assert_eq(r.remainder, 30)
	assert_eq(inv.get_stack(0).count, 30)


func test_quick_move_respects_source_policy() -> void:
	var oc := InvOpenContext.new()
	var locked := _c(1)
	locked.policy = LockedPolicy.new()
	var inv := _c(1)
	_put(locked, 0, wood, 30)
	oc.open(inv)
	oc.open(locked, &"external")
	var r := oc.quick_move(locked, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.LOCKED)
	assert_eq(locked.get_stack(0).count, 30)
	assert_true(inv.is_slot_empty(0))


func test_quick_move_respects_target_filter() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	var toolbox := _c(2)
	var f := InvSlotFilter.new()
	f.required_tags = [&"tool"]
	toolbox.set_all_filters(f)
	_put(inv, 0, wood, 30)
	oc.open(inv)
	oc.open(toolbox, &"external")
	var r := oc.quick_move(inv, 0)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.WRONG_TYPE)
	assert_eq(inv.get_stack(0).count, 30)


func test_quick_move_empty_and_invalid() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(1)
	oc.open(inv)
	assert_eq(oc.quick_move(inv, 0).hint, InvDropCheck.EMPTY)
	assert_eq(oc.quick_move(inv, 5).hint, InvDropCheck.INVALID_INDEX)
	assert_eq(oc.quick_move(null, 0).hint, InvDropCheck.INVALID_INDEX)


func test_context_collect_scopes_to_open_containers() -> void:
	var oc := InvOpenContext.new()
	var inv := _c(2)
	var chest := _c(1)
	var closed := _c(1)
	_put(inv, 0, wood, 10)
	_put(inv, 1, wood, 10)
	_put(chest, 0, wood, 10)
	_put(closed, 0, wood, 10)
	oc.open(inv)
	oc.open(chest, &"external")
	var h := InvHeldStack.new()
	h.pickup(inv, 0)
	assert_eq(oc.collect(h), 20)
	assert_eq(h.count(), 30)
	assert_eq(closed.get_stack(0).count, 10, "closed container untouched")
