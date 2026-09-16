@tool
class_name InvHotbar
extends RefCounted

## Selection state over an InvContainer (the hotbar's slots are ordinary
## slots — the container is usually also registered with the UI session so
## items can be dragged into it). Tracks which slot is "active" and tells
## the game when the active item changes for any reason (selection moved,
## item swapped in, stack consumed).
##
## Input: call handle_input(event) from the game's _unhandled_input.
## Actions `inv_hotbar_next` / `inv_hotbar_prev` and `inv_hotbar_1`..`_9`
## are used when present in the InputMap; otherwise mouse wheel and the
## digit keys 1-9 are used when the matching `use_*` flag is on.

signal selection_changed(index: int)
## The def in the active slot changed (or its count did). def may be null.
signal active_changed(index: int, stack: InvItemStack)

var container: InvContainer
var selected: int = 0:
	set = select

var use_wheel: bool = true
var use_number_keys: bool = true
var wrap: bool = true

var _last_def: InvItemDef = null
var _last_count: int = 0


func _init(p_container: InvContainer) -> void:
	container = p_container
	container.slot_changed.connect(_on_slot_changed)
	_sync_active(false)


func size() -> int:
	return container.size()


func select(i: int) -> void:
	if container == null or container.size() == 0:
		return
	if wrap:
		i = posmod(i, container.size())
	else:
		i = clampi(i, 0, container.size() - 1)
	if i == selected:
		return
	selected = i
	selection_changed.emit(selected)
	_sync_active(true, true)


func select_next() -> void:
	select(selected + 1)


func select_prev() -> void:
	select(selected - 1)


func active_stack() -> InvItemStack:
	return container.get_stack(selected)


func active_def() -> InvItemDef:
	return active_stack().def


## Remove `n` from the active stack (e.g. after planting a seed). Goes through
## the container's policy. Returns false if not enough / locked.
func consume_active(n: int = 1, ctx: InvTransferContext = null) -> bool:
	var s := active_stack()
	if s.is_empty() or s.count < n:
		return false
	var rc := container.check_remove(selected, n, ctx)
	if not rc.ok or rc.capacity < n:
		return false
	var od := s.def
	var oc := s.count
	s.split_off(n)
	container.notify_slot_mutated(selected, od, oc)
	return true


## Use the active item on `user` (see InvUsableComponent). Returns the
## use result: CONSUME / CHANGED / NOOP / FAILED.
func use_active(user: Variant, ctx: InvTransferContext = null) -> StringName:
	return InvUsableComponent.use_slot(container, selected, user, ctx)


## Usable component of the active item, or null (for prompts: "E: Eat").
func active_usable() -> InvUsableComponent:
	return InvUsableComponent.find(active_def())


## Re-emit change for the active slot after mutating its stack.data.
func touch_active() -> void:
	container.touch(selected)


## Returns true if the event was consumed.
func handle_input(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if _action(event, &"inv_hotbar_next"):
		select_next()
		return true
	if _action(event, &"inv_hotbar_prev"):
		select_prev()
		return true
	for n in range(1, 10):
		if _action(event, StringName("inv_hotbar_%d" % n)):
			if n - 1 < container.size():
				select(n - 1)
			return true
	if use_wheel and event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_next()
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_prev()
			return true
	if use_number_keys and event is InputEventKey and event.is_pressed():
		var k := event as InputEventKey
		var code := k.keycode
		if code >= KEY_1 and code <= KEY_9:
			var idx := int(code - KEY_1)
			if idx < container.size():
				select(idx)
				return true
	return false


static func _action(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


func _on_slot_changed(i: int) -> void:
	# Any change to the active slot is reported, including data-only ones
	# (water level, durability) signalled via container.touch().
	if i == selected:
		_sync_active(true, true)


func _sync_active(emit: bool, force: bool = false) -> void:
	var s := active_stack()
	if not force and s.def == _last_def and s.count == _last_count:
		return
	_last_def = s.def
	_last_count = s.count
	if emit:
		active_changed.emit(selected, s)
