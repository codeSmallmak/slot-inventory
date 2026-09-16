@tool
class_name InvCursorView
extends Control

## Draws the held stack under the pointer (or snapped to the focused slot
## in controller mode). Pure presentation; bound to an InvHeldStack.
##
## Theming (type "InvCursorView"): colors count_color, count_shadow;
## fonts count_font; font_sizes count_font_size; constants count_margin.

@export var theme_type: StringName = &"InvCursorView"
@export var icon_size: Vector2 = Vector2(40, 40)
## Pointer-relative offset of the icon's top-left in follow mode.
@export var follow_offset: Vector2 = Vector2(-20, -20)
## Follow the mouse. Turned off by snap_to() (controller mode) and back on
## by the next mouse motion when auto_follow_on_mouse is true.
@export var follow_mouse: bool = true
@export var auto_follow_on_mouse: bool = true

var held: InvHeldStack = null
var _snap_target: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 100
	focus_mode = Control.FOCUS_NONE
	visible = false


func bind(h: InvHeldStack) -> void:
	if held != null and held.changed.is_connected(_on_held_changed):
		held.changed.disconnect(_on_held_changed)
	held = h
	if held != null:
		held.changed.connect(_on_held_changed)
	_on_held_changed()


## Controller mode: park the cursor over `target` until the mouse moves.
func snap_to(target: Control) -> void:
	_snap_target = target
	follow_mouse = false
	_reposition()


func _on_held_changed() -> void:
	visible = held != null and held.is_holding()
	size = icon_size
	if visible:
		_reposition()
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not visible:
		return
	_reposition()


func _input(event: InputEvent) -> void:
	if auto_follow_on_mouse and not follow_mouse and event is InputEventMouseMotion:
		follow_mouse = true
		_snap_target = null


func _reposition() -> void:
	if follow_mouse:
		global_position = get_global_mouse_position() + follow_offset
	elif _snap_target != null and is_instance_valid(_snap_target):
		var r := _snap_target.get_global_rect()
		global_position = r.position + (r.size - icon_size) * 0.5 + Vector2(6, 6)


func _draw() -> void:
	if held == null or not held.is_holding():
		return
	var s := held.stack()
	var rect := Rect2(Vector2.ZERO, icon_size)
	if s.def.icon != null:
		draw_texture_rect(s.def.icon, InvSlotView._fit(rect, s.def.icon.get_size()), false)
	else:
		draw_rect(rect, Color(0.5, 0.5, 0.55, 0.8))
	if s.count > 1:
		var font := get_theme_font(&"count_font", theme_type)
		var fs := get_theme_font_size(&"count_font_size", theme_type)
		if fs <= 0:
			fs = 12
		var m := float(get_theme_constant(&"count_margin", theme_type)) if has_theme_constant(&"count_margin", theme_type) else 2.0
		var text := str(s.count)
		var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs)
		var pos := Vector2(rect.end.x - m - tsize.x, rect.end.y - m - font.get_descent(fs))
		var sh := get_theme_color(&"count_shadow", theme_type) if has_theme_color(&"count_shadow", theme_type) else Color(0, 0, 0, 0.85)
		var col := get_theme_color(&"count_color", theme_type) if has_theme_color(&"count_color", theme_type) else Color.WHITE
		draw_string(font, pos + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
