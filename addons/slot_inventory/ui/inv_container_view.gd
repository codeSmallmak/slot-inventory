@tool
class_name InvContainerView
extends InvSlotsView

## Grid of InvSlotViews bound to one InvContainer. Lays its slots out in
## `columns` with `h_separation` / `v_separation` (like GridContainer, but
## the children are always our own slot views). Never mutates data.
##
## Set `preview_slots` to see placeholder slots in the editor for theming.
## Set `slot_scene` to use a custom slot (root must extend InvSlotView).

@export_range(1, 64) var columns: int = 5:
	set(v):
		columns = maxi(v, 1)
		queue_sort()
		update_minimum_size()
@export var h_separation: int = 4:
	set(v):
		h_separation = v
		queue_sort()
		update_minimum_size()
@export var v_separation: int = 4:
	set(v):
		v_separation = v
		queue_sort()
		update_minimum_size()
@export var slot_size: Vector2 = Vector2(48, 48):
	set(v):
		slot_size = v
		for s in _views:
			s.slot_size = v
		queue_sort()
		update_minimum_size()
## Optional custom slot scene. Root must extend InvSlotView.
@export var slot_scene: PackedScene = null
## Editor-only: number of placeholder slots to show when nothing is bound.
@export var preview_slots: int = 0:
	set(v):
		preview_slots = v
		if Engine.is_editor_hint() and container == null:
			_rebuild_preview()


func _ready() -> void:
	if Engine.is_editor_hint() and container == null:
		_rebuild_preview()


func bind(c: InvContainer) -> void:
	container = c
	_rebuild(c.size() if c != null else 0)


# ------------------------------------------------------------------- layout

func _rows() -> int:
	return ceili(float(_views.size()) / columns) if not _views.is_empty() else 0


func _get_minimum_size() -> Vector2:
	var n := _views.size()
	if n == 0:
		return Vector2.ZERO
	var cols := mini(columns, n)
	var rows := _rows()
	return Vector2(cols * slot_size.x + (cols - 1) * h_separation,
			rows * slot_size.y + (rows - 1) * v_separation)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for i in _views.size():
			var v := _views[i]
			var col := i % columns
			var row := floori(float(i) / columns)
			var pos := Vector2(col * (slot_size.x + h_separation), row * (slot_size.y + v_separation))
			fit_child_in_rect(v, Rect2(pos, slot_size))


# ---------------------------------------------------------------- internals

func _rebuild_preview() -> void:
	_rebuild(preview_slots)
	var fake := InvContainer.new(preview_slots, &"preview")
	for i in _views.size():
		_views[i].bind(fake, i)


func _rebuild(n: int) -> void:
	for v in _views:
		v.queue_free()
	_views.clear()
	for i in n:
		var v := _make_slot()
		v.name = "Slot%d" % i
		v.slot_size = slot_size
		v.bind(container, i)
		_wire(v)
		add_child(v)
		_views.append(v)
	queue_sort()
	update_minimum_size()
	rebuilt.emit()


func _make_slot() -> InvSlotView:
	if slot_scene != null:
		var inst := slot_scene.instantiate()
		if inst is InvSlotView:
			return inst
		push_warning("InvContainerView: slot_scene root is not an InvSlotView; using default")
		inst.free()
	return InvSlotView.new()
