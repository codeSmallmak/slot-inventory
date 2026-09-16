@tool
extends McpTestSuite

## Phase 3 headless tests: InvUISession input interpretation through real
## InvContainerView / InvSlotView nodes (kept OFF the scene tree — no
## rendering, no tweens). Events are synthesised and fed to the slot's
## _gui_input, so the whole view -> session -> data chain is exercised.


class LockedPolicy extends InvContainerPolicy:
	func can_remove(_c: InvContainer, _i: int, _n: int, _ctx: InvTransferContext) -> InvDropCheck:
		return InvDropCheck.reject(InvDropCheck.LOCKED)


var db: InvItemDatabase
var wood: InvItemDef
var stone: InvItemDef
var axe: InvItemDef


func suite_name() -> String:
	return "inv_ui"


func suite_setup(_ctx: Dictionary) -> void:
	db = InvItemDatabase.new()
	wood = _def(&"wood", 50)
	stone = _def(&"stone", 50)
	axe = _def(&"axe", 1)


func _def(id: StringName, max_stack: int) -> InvItemDef:
	var d := InvItemDef.new()
	d.id = id
	d.max_stack = max_stack
	db.register(d)
	return d


func _session() -> InvUISession:
	var s := InvUISession.new()
	s.shake_on_reject = false
	track(s)
	return s


## Container view laid out manually (no tree => GridContainer won't sort).
func _view(c: InvContainer, group: StringName, origin: Vector2 = Vector2.ZERO) -> InvContainerView:
	var v := InvContainerView.new()
	v.group = group
	v.bind(c)
	for i in v.slot_count():
		var sv := v.get_view(i)
		sv.animate_changes = false
		sv.size = Vector2(48, 48)
		sv.position = origin + Vector2(i * 50, 0)
	track(v)
	return v


func _put(c: InvContainer, i: int, def: InvItemDef, n: int) -> void:
	c.set_stack(i, InvItemStack.make(def, n))


func _mb(button: int, pressed: bool, pos: Vector2 = Vector2.ZERO, shift: bool = false, dbl: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.global_position = pos
	e.position = pos
	e.shift_pressed = shift
	e.double_click = dbl
	return e


func _click(view: InvSlotView, button: int = MOUSE_BUTTON_LEFT, shift: bool = false, dbl: bool = false) -> void:
	var pos := view.get_global_rect().get_center()
	view._gui_input(_mb(button, true, pos, shift, dbl))
	view._gui_input(_mb(button, false, pos, shift, dbl))


# ------------------------------------------------------------- registration

func test_register_opens_in_group() -> void:
	var s := _session()
	var inv := InvContainer.new(4)
	var chest := InvContainer.new(4)
	var iv := _view(inv, &"player")
	var cv := _view(chest, &"external")
	s.register(iv)
	s.register(cv)
	assert_true(s.open.is_open(inv))
	assert_eq(s.open.group_of(chest), &"external")
	s.register(iv)  # idempotent
	assert_eq(s.registered_views().size(), 2)
	s.unregister(cv)
	assert_false(s.open.is_open(chest))
	assert_eq(s.registered_views().size(), 1)


func test_register_group_override_and_unregister_group() -> void:
	var s := _session()
	var a := InvContainer.new(1)
	var b := InvContainer.new(1)
	var av := _view(a, &"player")
	var bv := _view(b, &"player")
	s.register(av)
	s.register(bv, &"external")
	assert_eq(s.open.group_of(b), &"external")
	s.unregister_group(&"external")
	assert_false(s.open.is_open(b))
	assert_true(s.open.is_open(a))


# ------------------------------------------------------------------- clicks

func test_lmb_pickup_then_place() -> void:
	var s := _session()
	var inv := InvContainer.new(4)
	_put(inv, 0, wood, 10)
	var iv := _view(inv, &"player")
	s.register(iv)
	_click(iv.get_view(0))
	assert_true(s.held.is_holding())
	assert_eq(s.held.count(), 10)
	assert_true(inv.is_slot_empty(0))
	_click(iv.get_view(2))
	assert_false(s.held.is_holding())
	assert_eq(inv.get_stack(2).count, 10)


func test_lmb_swap_and_click_empty_hand_on_empty_is_silent() -> void:
	var s := _session()
	var inv := InvContainer.new(2)
	_put(inv, 0, wood, 10)
	_put(inv, 1, stone, 3)
	var iv := _view(inv, &"player")
	s.register(iv)
	var rejected := [0]
	s.transfer_rejected.connect(func(_r: InvTransferResult) -> void: rejected[0] += 1)
	var committed := [0]
	s.transfer_committed.connect(func(_r: InvTransferResult) -> void: committed[0] += 1)
	_click(iv.get_view(0))
	_click(iv.get_view(1))
	assert_eq(s.held.def(), stone)
	assert_eq(inv.get_stack(1).def, wood)
	assert_eq(committed[0], 2)
	_click(iv.get_view(0))  # place stone into empty 0
	_click(iv.get_view(0))  # pick it up again
	_click(iv.get_view(0))  # put it back
	assert_false(s.held.is_holding())
	_click(iv.get_view(1))  # pick wood
	_click(iv.get_view(1))  # ... and back
	var empty_inv := InvContainer.new(1)
	var ev := _view(empty_inv, &"player")
	s.register(ev)
	_click(ev.get_view(0))  # empty hand on empty slot
	assert_eq(rejected[0], 0, "empty-on-empty is not a rejection")


func test_rmb_half_then_one() -> void:
	var s := _session()
	var inv := InvContainer.new(2)
	_put(inv, 0, wood, 10)
	var iv := _view(inv, &"player")
	s.register(iv)
	_click(iv.get_view(0), MOUSE_BUTTON_RIGHT)
	assert_eq(s.held.count(), 5)
	assert_eq(inv.get_stack(0).count, 5)
	_click(iv.get_view(1), MOUSE_BUTTON_RIGHT)
	_click(iv.get_view(1), MOUSE_BUTTON_RIGHT)
	assert_eq(s.held.count(), 3)
	assert_eq(inv.get_stack(1).count, 2)


func test_drag_release_over_other_slot_places() -> void:
	var s := _session()
	var inv := InvContainer.new(3)
	_put(inv, 0, wood, 10)
	var iv := _view(inv, &"player")
	s.register(iv)
	var a := iv.get_view(0)
	var b := iv.get_view(2)
	a._gui_input(_mb(MOUSE_BUTTON_LEFT, true, a.get_global_rect().get_center()))
	assert_true(s.held.is_holding())
	# Godot routes the release to the pressed control, with the new position.
	a._gui_input(_mb(MOUSE_BUTTON_LEFT, false, b.get_global_rect().get_center()))
	assert_false(s.held.is_holding())
	assert_eq(inv.get_stack(2).count, 10)


func test_release_over_same_slot_keeps_holding() -> void:
	var s := _session()
	var inv := InvContainer.new(2)
	_put(inv, 0, wood, 10)
	var iv := _view(inv, &"player")
	s.register(iv)
	_click(iv.get_view(0))
	assert_true(s.held.is_holding())
	assert_eq(s.held.count(), 10)


func test_release_over_nothing_keeps_holding() -> void:
	var s := _session()
	var inv := InvContainer.new(2)
	_put(inv, 0, wood, 10)
	var iv := _view(inv, &"player")
	s.register(iv)
	var a := iv.get_view(0)
	a._gui_input(_mb(MOUSE_BUTTON_LEFT, true, a.get_global_rect().get_center()))
	a._gui_input(_mb(MOUSE_BUTTON_LEFT, false, Vector2(-500, -500)))
	assert_true(s.held.is_holding())


func test_shift_click_quick_moves_to_external() -> void:
	var s := _session()
	var inv := InvContainer.new(2)
	var chest := InvContainer.new(2)
	_put(inv, 0, wood, 10)
	_put(chest, 1, wood, 45)
	var iv := _view(inv, &"player")
	var cv := _view(chest, &"external", Vector2(0, 100))
	s.register(iv)
	s.register(cv)
	_click(iv.get_view(0), MOUSE_BUTTON_LEFT, true)
	assert_false(s.held.is_holding())
	assert_true(inv.is_slot_empty(0))
	assert_eq(chest.get_stack(1).count, 50)
	assert_eq(chest.get_stack(0).count, 5)


func test_double_click_collects_from_open_containers() -> void:
	var s := _session()
	var inv := InvContainer.new(3)
	var chest := InvContainer.new(2)
	_put(inv, 0, wood, 10)
	_put(inv, 2, wood, 10)
	_put(chest, 0, wood, 10)
	var iv := _view(inv, &"player")
	var cv := _view(chest, &"external", Vector2(0, 100))
	s.register(iv)
	s.register(cv)
	var v0 := iv.get_view(0)
	var pos := v0.get_global_rect().get_center()
	v0._gui_input(_mb(MOUSE_BUTTON_LEFT, true, pos))
	v0._gui_input(_mb(MOUSE_BUTTON_LEFT, false, pos))
	v0._gui_input(_mb(MOUSE_BUTTON_LEFT, true, pos, false, true))
	v0._gui_input(_mb(MOUSE_BUTTON_LEFT, false, pos, false, true))
	assert_eq(s.held.count(), 30)
	assert_true(inv.is_slot_empty(2))
	assert_true(chest.is_slot_empty(0))


func test_rejected_transfer_emits_signal() -> void:
	var s := _session()
	var locked := InvContainer.new(1)
	locked.policy = LockedPolicy.new()
	_put(locked, 0, wood, 10)
	var lv := _view(locked, &"external")
	s.register(lv)
	var hints := []
	s.transfer_rejected.connect(func(r: InvTransferResult) -> void: hints.append(r.hint))
	_click(lv.get_view(0))
	assert_false(s.held.is_holding())
	assert_eq(hints.size(), 1)
	assert_eq(hints[0], InvDropCheck.LOCKED)


# ----------------------------------------------------------- hover feedback

func test_hover_feedback_and_glow() -> void:
	var s := _session()
	var inv := InvContainer.new(3)
	_put(inv, 0, wood, 10)
	_put(inv, 1, stone, 1)
	_put(inv, 2, wood, 50)
	var iv := _view(inv, &"player")
	s.register(iv)
	var v1 := iv.get_view(1)
	v1._notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_eq(s.hover_view, v1)
	assert_eq(v1.feedback, null, "no feedback while hand is empty")
	_click(iv.get_view(0))
	# Held changed -> feedback recomputed on the hovered slot.
	assert_true(v1.feedback != null)
	assert_eq(v1.feedback.hint, InvDropCheck.SWAP)
	assert_false(v1.accepts_held, "swap targets don't glow")
	assert_true(iv.get_view(0).accepts_held, "empty slot glows")
	assert_false(iv.get_view(2).accepts_held, "full stack of same item doesn't glow")
	v1._notification(Control.NOTIFICATION_MOUSE_EXIT)
	assert_eq(s.hover_view, null)
	assert_eq(v1.feedback, null)
	_click(iv.get_view(0))
	assert_false(iv.get_view(0).accepts_held, "glow cleared when hand empties")


func test_focus_acts_as_hover() -> void:
	var s := _session()
	var inv := InvContainer.new(2)
	_put(inv, 0, wood, 10)
	var iv := _view(inv, &"player")
	s.register(iv)
	_click(iv.get_view(0))
	var v1 := iv.get_view(1)
	v1._notification(Control.NOTIFICATION_FOCUS_ENTER)
	assert_eq(s.hover_view, v1)
	assert_true(v1.feedback != null and v1.feedback.ok)


# ------------------------------------------------------------ return / drop

func test_return_held_falls_back_to_player_group_then_signals() -> void:
	var s := _session()
	var inv := InvContainer.new(1)
	var chest := InvContainer.new(1)
	_put(chest, 0, wood, 10)
	var iv := _view(inv, &"player")
	var cv := _view(chest, &"external", Vector2(0, 100))
	s.register(iv)
	s.register(cv)
	_click(cv.get_view(0))
	_put(chest, 0, stone, 50)  # origin blocked
	assert_eq(s.return_held(&"player"), 0)
	assert_eq(inv.get_stack(0).count, 10)

	# Now nothing can take it: signal fires, item stays held for the game.
	_click(iv.get_view(0))
	_put(inv, 0, stone, 50)
	var got := []
	s.drop_outside_requested.connect(func(h: InvHeldStack) -> void: got.append(h.count()))
	assert_eq(s.return_held(&"player"), 10)
	assert_eq(got, [10])
	assert_true(s.held.is_holding())
	var taken := s.held.take()
	assert_eq(taken.count, 10)
	assert_false(s.held.is_holding())


func test_unregister_clears_hover_and_glow() -> void:
	var s := _session()
	var inv := InvContainer.new(2)
	var chest := InvContainer.new(2)
	_put(inv, 0, wood, 10)
	var iv := _view(inv, &"player")
	var cv := _view(chest, &"external", Vector2(0, 100))
	s.register(iv)
	s.register(cv)
	_click(iv.get_view(0))
	var c0 := cv.get_view(0)
	c0._notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_true(c0.accepts_held)
	assert_eq(s.hover_view, c0)
	s.unregister(cv)
	assert_false(c0.accepts_held)
	assert_eq(s.hover_view, null)
