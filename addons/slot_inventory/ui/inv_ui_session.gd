@tool
class_name InvUISession
extends Node

## The input layer. Owns the cursor's InvHeldStack, the InvOpenContext and
## the InvTransferContext, and turns raw slot input (mouse, touch-as-mouse,
## controller actions) into InvHeldStack / InvOpenContext calls. It is the
## ONLY place UI intent is interpreted; views never touch data.
##
## Mouse / touch:
##   LMB press          empty hand: pick up all      holding: place all / swap
##   LMB press + drag   release over another slot places there (hybrid drag)
##   RMB press          empty hand: pick up half     holding: place one
##   Shift + LMB        quick-move (routed by InvOpenContext)
##   LMB double-click   while holding: collect matching stacks from open containers
##   LMB outside slots  drop_outside_requested (game decides; see held.take())
## Vendor slots (container policy with bulk_pickup_enabled(), i.e. shops):
##   LMB / RMB          take 1 into the hand (a purchase)
##   Shift / Ctrl / both   take bulk_shift / bulk_ctrl / bulk_both units
##   LMB held           repeats "take 1" after hold_repeat_delay, accelerating
##   no quick-move, no collect, no half-stack pickup on vendor slots
## Controller / keyboard: focus a slot, then the actions below. `ui_accept`
## stands in for the primary action when `inv_primary` is not in the InputMap.
##
## Register each InvSlotsView (container/hotbar/equipment view) with
## register(); it joins the open
## context under its group. Call return_held() before hiding a screen.

signal transfer_committed(result: InvTransferResult)
signal transfer_rejected(result: InvTransferResult)
## Primary pressed outside every slot while holding. The game decides:
## `held.take()` to drop it in the world, or do nothing to keep it held.
signal drop_outside_requested(held: InvHeldStack)
signal hover_changed(view: InvSlotView)

@export var primary_action: StringName = &"inv_primary"
@export var secondary_action: StringName = &"inv_secondary"
## Held modifier that turns primary into quick-move (Shift on mouse always works).
@export var quick_action: StringName = &"inv_quick"
@export var collect_action: StringName = &"inv_collect"
@export var drag_to_place: bool = true
@export var double_click_collects: bool = true
@export var drop_outside_enabled: bool = true
@export var shake_on_reject: bool = true
## Slots in the hovered container that could take the held stack get a glow.
@export var show_accepts_glow: bool = true

@export_group("Tooltip")
## Seconds of hover before the tooltip appears. 0 = immediate.
@export var tooltip_delay: float = 0.35
## Show tooltips for slots while an item is on the cursor.
@export var tooltip_while_holding: bool = false
@export_group("Vendor bulk pickup")
@export var bulk_shift: int = 5
@export var bulk_ctrl: int = 10
@export var bulk_both: int = 25
@export var hold_repeat: bool = true
## Seconds the button must be held before repeating starts.
@export var hold_repeat_delay: float = 0.45
## Seconds between repeats at the start; shrinks toward hold_repeat_min.
@export var hold_repeat_interval: float = 0.16
@export var hold_repeat_min: float = 0.04
@export var hold_repeat_accel: float = 0.85
@export_group("")

var held: InvHeldStack = InvHeldStack.new()
var open: InvOpenContext = InvOpenContext.new()
var ctx: InvTransferContext = InvTransferContext.new()
var cursor: InvCursorView = null
var tooltip: InvTooltipView = null
var hover_view: InvSlotView = null

var _views: Array[InvSlotsView] = []
var _groups: Dictionary = {}  # InvSlotsView -> StringName
var _press_view: InvSlotView = null

var _tooltip_pending: InvSlotView = null
var _tooltip_t: float = 0.0

var _hold_view: InvSlotView = null
var _hold_t: float = 0.0
var _hold_next: float = 0.0
var _hold_interval: float = 0.0


func _init() -> void:
	ctx.open_context = open
	held.changed.connect(_on_held_changed)


# ------------------------------------------------------------------- wiring

func set_cursor(c: InvCursorView) -> void:
	cursor = c
	if cursor != null:
		cursor.bind(held)


func set_tooltip(t: InvTooltipView) -> void:
	if tooltip != null and tooltip != t:
		tooltip.hide_tip()
	tooltip = t


## Anything exposing get_gold()/try_spend()/add_gold(); forwarded to policies.
func set_wallet(w: Object) -> void:
	ctx.wallet = w


func register(view: InvSlotsView, group: StringName = &"") -> void:
	if view == null or view.container == null:
		push_warning("InvUISession.register: view is null or unbound")
		return
	if _views.has(view):
		return
	var g := group if group != &"" else view.group
	_views.append(view)
	_groups[view] = g
	open.open(view.container, g)
	view.slot_input.connect(_on_slot_input)
	view.slot_hover_changed.connect(_on_slot_hover)
	view.slot_focused.connect(_on_slot_focused)
	for v in view.views():
		v.ctx = ctx
	_refresh_accepts(view)


func unregister(view: InvSlotsView) -> void:
	var at := _views.find(view)
	if at == -1:
		return
	_views.remove_at(at)
	_groups.erase(view)
	open.close(view.container)
	view.slot_input.disconnect(_on_slot_input)
	view.slot_hover_changed.disconnect(_on_slot_hover)
	view.slot_focused.disconnect(_on_slot_focused)
	if hover_view != null and hover_view.container == view.container:
		_set_hover(null)
	if _hold_view != null and _hold_view.container == view.container:
		_stop_hold()
	for v in view.views():
		v.accepts_held = false


func unregister_group(group: StringName) -> void:
	for v in _views.duplicate():
		if _groups.get(v, &"") == group:
			unregister(v)


func unregister_all() -> void:
	for v in _views.duplicate():
		unregister(v)


func registered_views() -> Array[InvSlotsView]:
	return _views.duplicate()


# ------------------------------------------------------------- held helpers

## Put the held stack back (origin slot -> origin container -> every open
## container in `fallback_group`). Anything left triggers
## drop_outside_requested so the game can world-drop it. Returns leftover.
func return_held(fallback_group: StringName = &"player") -> int:
	if not held.is_holding():
		return 0
	var left := held.return_home_or(open.containers_in(fallback_group), ctx)
	if left > 0:
		drop_outside_requested.emit(held)
	return held.count()


## Game-side hook when the player presses outside the UI while holding.
func request_drop_outside() -> void:
	if held.is_holding():
		drop_outside_requested.emit(held)


# ------------------------------------------------------------------ actions

func primary(view: InvSlotView) -> InvTransferResult:
	var r: InvTransferResult
	if held.is_holding():
		r = held.place(view.container, view.index, -1, ctx)
	else:
		r = held.pickup(view.container, view.index, -1, ctx)
	_report(r, view)
	return r


func secondary(view: InvSlotView) -> InvTransferResult:
	var r: InvTransferResult
	if held.is_holding():
		r = held.place_one(view.container, view.index, ctx)
	else:
		r = held.pickup_half(view.container, view.index, ctx)
	_report(r, view)
	return r


func quick_move(view: InvSlotView) -> InvTransferResult:
	var r := open.quick_move(view.container, view.index, -1, ctx)
	_report(r, view)
	return r


func collect(_view: InvSlotView = null) -> int:
	var n := open.collect(held, ctx)
	_update_feedback()
	return n


## Vendor pickup: take `n` units of view's stack into the hand (merging with
## what is already held). The policy caps n by funds; the hand caps it by
## max_stack. Holding a different item does nothing (no swaps with shops).
func take(view: InvSlotView, n: int = 1) -> InvTransferResult:
	var r: InvTransferResult
	if held.is_holding() and held.def() != view.stack().def:
		r = InvTransferResult.failure(InvDropCheck.SWAP_BLOCKED, view.container, view.index, held.container(), 0)
	else:
		r = held.pickup(view.container, view.index, n, ctx)
	_report(r, view)
	return r


static func is_vendor(view: InvSlotView) -> bool:
	return view != null and view.container != null and view.container.policy != null \
		and view.container.policy.bulk_pickup_enabled()


func _bulk_count(shift: bool, ctrl: bool) -> int:
	if shift and ctrl:
		return bulk_both
	if ctrl:
		return bulk_ctrl
	if shift:
		return bulk_shift
	return 1


# -------------------------------------------------------------------- input

func _on_slot_input(view: InvSlotView, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(view, event as InputEventMouseButton)
		return
	if event.is_echo():
		return
	if _pressed(event, collect_action, &""):
		if held.is_holding():
			collect(view)
		view.accept_event()
	elif _pressed(event, primary_action, &"ui_accept"):
		if is_vendor(view):
			take(view, bulk_shift if _quick_modifier_down() else 1)
		elif _quick_modifier_down():
			quick_move(view)
		else:
			primary(view)
		view.accept_event()
	elif _pressed(event, secondary_action, &""):
		if is_vendor(view):
			take(view, 1)
		else:
			secondary(view)
		view.accept_event()


func _mouse_button(view: InvSlotView, mb: InputEventMouseButton) -> void:
	if is_vendor(view):
		_vendor_mouse_button(view, mb)
		return
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click and double_click_collects and held.is_holding():
					collect(view)
					_press_view = null
				elif mb.shift_pressed or _quick_modifier_down():
					quick_move(view)
					_press_view = null
				else:
					primary(view)
					_press_view = view if held.is_holding() else null
			else:
				if drag_to_place and _press_view != null and held.is_holding():
					var target := view_at(mb.global_position)
					if target != null and target != _press_view:
						primary(target)
				_press_view = null
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				secondary(view)


func _vendor_mouse_button(view: InvSlotView, mb: InputEventMouseButton) -> void:
	_press_view = null
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var n := _bulk_count(mb.shift_pressed, mb.ctrl_pressed)
			var r := take(view, n)
			if hold_repeat and n == 1 and r.ok:
				_start_hold(view)
			else:
				_stop_hold()
		else:
			_stop_hold()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		take(view, 1)


func _start_hold(view: InvSlotView) -> void:
	_hold_view = view
	_hold_t = 0.0
	_hold_next = hold_repeat_delay
	_hold_interval = hold_repeat_interval
	set_process(true)


func _stop_hold() -> void:
	_hold_view = null


func _process(delta: float) -> void:
	if _tooltip_pending != null:
		tick_tooltip(delta)
	if _hold_view == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not is_instance_valid(_hold_view):
		_stop_hold()
		return
	tick_hold(delta)


## Advance the tooltip delay. Called from _process; exposed for tests.
func tick_tooltip(delta: float) -> void:
	if _tooltip_pending == null or tooltip == null:
		return
	_tooltip_t += delta
	if _tooltip_t >= tooltip_delay:
		var v := _tooltip_pending
		_tooltip_pending = null
		if is_instance_valid(v) and v == hover_view:
			tooltip.show_for(v, ctx)


func _schedule_tooltip(view: InvSlotView) -> void:
	if tooltip == null:
		return
	if view == null or (held.is_holding() and not tooltip_while_holding):
		_tooltip_pending = null
		tooltip.hide_tip()
		return
	if tooltip.is_showing_for(view):
		return
	tooltip.hide_tip()
	_tooltip_pending = view
	_tooltip_t = 0.0
	if tooltip_delay <= 0.0:
		tick_tooltip(0.0)


## Advance the hold-to-repeat timer. Called from _process; exposed so
## headless tests (and custom input schemes) can drive it.
func tick_hold(delta: float) -> void:
	if _hold_view == null:
		return
	_hold_t += delta
	while _hold_view != null and _hold_t >= _hold_next:
		var r := take(_hold_view, 1)
		if not r.ok:
			_stop_hold()
			return
		_hold_interval = maxf(hold_repeat_min, _hold_interval * hold_repeat_accel)
		_hold_next += _hold_interval


func is_hold_repeating() -> bool:
	return _hold_view != null


func _unhandled_input(event: InputEvent) -> void:
	if not drop_outside_enabled or not held.is_holding():
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		drop_outside_requested.emit(held)
		get_viewport().set_input_as_handled()


static func _pressed(event: InputEvent, action: StringName, fallback: StringName) -> bool:
	if action != &"" and InputMap.has_action(action):
		return event.is_action_pressed(action)
	if fallback != &"" and InputMap.has_action(fallback):
		return event.is_action_pressed(fallback)
	return false


func _quick_modifier_down() -> bool:
	if quick_action != &"" and InputMap.has_action(quick_action):
		return Input.is_action_pressed(quick_action)
	return Input.is_key_pressed(KEY_SHIFT)


# --------------------------------------------------------------- hit testing

## Slot view under a global point across every registered view.
func view_at(global_pos: Vector2) -> InvSlotView:
	for cv in _views:
		var v := cv.view_at(global_pos)
		if v != null:
			return v
	return null


# ----------------------------------------------------------------- feedback

func _report(r: InvTransferResult, view: InvSlotView) -> void:
	if r.ok:
		transfer_committed.emit(r)
	else:
		# Clicking an empty slot with an empty hand is not a mistake.
		if r.hint != InvDropCheck.EMPTY and r.hint != InvDropCheck.NOOP:
			transfer_rejected.emit(r)
			if shake_on_reject and view != null:
				view.shake()
	_update_feedback()


func _on_slot_hover(view: InvSlotView, hovered: bool) -> void:
	if hovered:
		_set_hover(view)
	elif hover_view == view:
		_set_hover(null)


func _on_slot_focused(view: InvSlotView) -> void:
	_set_hover(view)
	if cursor != null:
		cursor.snap_to(view)


func _set_hover(view: InvSlotView) -> void:
	if hover_view == view:
		_update_feedback()
		return
	if hover_view != null:
		hover_view.feedback = null
	hover_view = view
	_update_feedback()
	_schedule_tooltip(view)
	hover_changed.emit(hover_view)


func _update_feedback() -> void:
	if hover_view == null:
		return
	if held.is_holding() and hover_view.is_bound():
		hover_view.feedback = held.preview(hover_view.container, hover_view.index, ctx)
	else:
		hover_view.feedback = null


func _on_held_changed() -> void:
	_update_feedback()
	_schedule_tooltip(hover_view)
	for cv in _views:
		_refresh_accepts(cv)


func _refresh_accepts(cv: InvSlotsView) -> void:
	var holding := show_accepts_glow and held.is_holding()
	var s := held.stack()
	for v in cv.views():
		if not holding or not v.is_bound():
			v.accepts_held = false
			continue
		var c := cv.container.check_insert(v.index, s, ctx)
		v.accepts_held = c.ok and c.hint != InvDropCheck.SWAP and c.capacity > 0
