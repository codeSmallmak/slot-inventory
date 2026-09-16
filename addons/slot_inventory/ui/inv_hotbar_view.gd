@tool
class_name InvHotbarView
extends InvContainerView

## A container grid that also shows an InvHotbar's selection: the active
## slot gets `selected = true` (theme stylebox "selected" on InvSlotView).
## Bind the container with bind() as usual, then bind_hotbar().

var hotbar: InvHotbar = null


func bind_hotbar(h: InvHotbar) -> void:
	if hotbar != null and hotbar.selection_changed.is_connected(_on_selection_changed):
		hotbar.selection_changed.disconnect(_on_selection_changed)
	hotbar = h
	if hotbar != null:
		if container != hotbar.container:
			bind(hotbar.container)
		hotbar.selection_changed.connect(_on_selection_changed)
		_on_selection_changed(hotbar.selected)


func _on_selection_changed(index: int) -> void:
	for i in _views.size():
		_views[i].selected = (i == index)


func _rebuild(n: int) -> void:
	super(n)
	if hotbar != null:
		_on_selection_changed(hotbar.selected)
