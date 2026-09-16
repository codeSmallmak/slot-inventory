@tool
class_name InvSlotsView
extends Container

## Base for anything that shows a set of InvSlotViews for ONE container and
## relays their input to an InvUISession: InvContainerView (grid),
## InvHotbarView (grid + selection), InvEquipmentView (hand-placed slots).
## Subclasses fill `_views` and call _wire(view) for each slot.

signal slot_input(view: InvSlotView, event: InputEvent)
signal slot_hover_changed(view: InvSlotView, hovered: bool)
signal slot_focused(view: InvSlotView)
signal rebuilt()

## InvOpenContext group this view's container joins when registered with
## an InvUISession (&"player", &"external", &"equipment", ...).
@export var group: StringName = &"player"

var container: InvContainer = null
var _views: Array[InvSlotView] = []


func bind(_c: InvContainer) -> void:
	push_error("InvSlotsView.bind: subclass must override")


func unbind() -> void:
	bind(null)


func get_view(i: int) -> InvSlotView:
	return _views[i] if i >= 0 and i < _views.size() else null


func views() -> Array[InvSlotView]:
	return _views


func slot_count() -> int:
	return _views.size()


## Slot view under a global point, or null.
func view_at(global_pos: Vector2) -> InvSlotView:
	for v in _views:
		if v.is_visible_in_tree() or not is_inside_tree():
			if v.get_global_rect().has_point(global_pos):
				return v
	return null


func refresh_all() -> void:
	for v in _views:
		v.refresh()


func _wire(v: InvSlotView) -> void:
	v.slot_input.connect(_on_slot_input)
	v.hover_changed.connect(_on_slot_hover)
	v.focused.connect(_on_slot_focused)


func _on_slot_input(view: InvSlotView, event: InputEvent) -> void:
	slot_input.emit(view, event)


func _on_slot_hover(view: InvSlotView, hovered: bool) -> void:
	slot_hover_changed.emit(view, hovered)


func _on_slot_focused(view: InvSlotView) -> void:
	slot_focused.emit(view)
