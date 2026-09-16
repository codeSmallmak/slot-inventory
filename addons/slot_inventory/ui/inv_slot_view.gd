@tool
class_name InvSlotView
extends Control

## One slot of one container. Pure presentation: draws whatever
## container[index] holds and reports raw input upward. Never mutates data.
##
## Theming (type "InvSlotView", override with `theme_type`):
##   styles:     normal, hover, focus, accept, reject, glow, selected
##   colors:     count_color, count_shadow, bar_bg, bar_fg, icon_modulate,
##               caption_color, caption_shadow
##   fonts:      count_font, caption_font
##   font_sizes: count_font_size, caption_font_size
##   constants:  icon_margin, count_margin, bar_height, count_shadow_offset,
##               caption_margin
## Every lookup falls back to a built-in default, so the view renders with
## no theme at all.
##
## Animation uses the Godot 4.7 Control offset transform (visual-only), so
## bumps and shakes never disturb container layout.

signal slot_input(view: InvSlotView, event: InputEvent)
signal hover_changed(view: InvSlotView, hovered: bool)
## Keyboard/controller focus landed here (the session treats it as hover).
signal focused(view: InvSlotView)

@export var theme_type: StringName = &"InvSlotView"
@export var slot_size: Vector2 = Vector2(48, 48):
	set(v):
		slot_size = v
		update_minimum_size()
## Pop the slot when its contents change.
@export var animate_changes: bool = true
## Hide the count label when count == 1.
@export var hide_single_count: bool = true

var container: InvContainer = null
var index: int = -1
## Optional; forwarded to policy.slot_caption() (prices may depend on it).
## The InvUISession sets this on register.
var ctx: InvTransferContext = null

## Drop feedback for the current hover, set by the session. null = none.
var feedback: InvDropCheck = null:
	set(v):
		feedback = v
		queue_redraw()
## Hotbar-style active marker (drawn over the background).
var selected: bool = false:
	set(v):
		if selected != v:
			selected = v
			queue_redraw()
## Soft highlight: "the held stack could go here". Set by the session.
var accepts_held: bool = false:
	set(v):
		if accepts_held != v:
			accepts_held = v
			queue_redraw()

var _hovered: bool = false
var _tween: Tween = null
var _last_count: int = 0

# Built-in fallbacks (used when the theme lacks an entry).
static var _fb_styles: Dictionary = {}


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	offset_transform_enabled = true
	offset_transform_visual_only = true
	offset_transform_pivot_ratio = Vector2(0.5, 0.5)


# ------------------------------------------------------------------ binding

func bind(p_container: InvContainer, p_index: int) -> void:
	if container != null and container.slot_changed.is_connected(_on_slot_changed):
		container.slot_changed.disconnect(_on_slot_changed)
	container = p_container
	index = p_index
	if container != null:
		container.slot_changed.connect(_on_slot_changed)
		_last_count = stack().count
	queue_redraw()


func unbind() -> void:
	bind(null, -1)


func is_bound() -> bool:
	return container != null and container.is_valid_index(index)


## Live stack (empty stack when unbound).
func stack() -> InvItemStack:
	if not is_bound():
		return InvItemStack.new()
	return container.get_stack(index)


func refresh() -> void:
	queue_redraw()


func _on_slot_changed(i: int) -> void:
	if i != index:
		return
	var n := stack().count
	if animate_changes and n != _last_count and n > 0:
		bump()
	_last_count = n
	queue_redraw()


# ---------------------------------------------------------------- animation

## Scale pop. Used on content change.
func bump(strength: float = 0.18, duration: float = 0.22) -> void:
	if not is_inside_tree():
		return
	_kill_tween()
	offset_transform_scale = Vector2.ONE * (1.0 + strength)
	_tween = create_tween()
	_tween.tween_property(self, "offset_transform_scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Horizontal shake. Used on rejected drop.
func shake(amplitude: float = 4.0, duration: float = 0.25) -> void:
	if not is_inside_tree():
		return
	_kill_tween()
	_tween = create_tween()
	var steps := 4
	for k in steps:
		var dir := 1.0 if k % 2 == 0 else -1.0
		var amp := amplitude * (1.0 - float(k) / steps)
		_tween.tween_property(self, "offset_transform_position", Vector2(dir * amp, 0.0), duration / (steps + 1))
	_tween.tween_property(self, "offset_transform_position", Vector2.ZERO, duration / (steps + 1))


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	offset_transform_scale = Vector2.ONE
	offset_transform_position = Vector2.ZERO


# ------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	slot_input.emit(self, event)
	var mb := event as InputEventMouseButton
	# Swallow clicks; let wheel and other buttons bubble (hotbar scrolling).
	if mb != null and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hovered = true
			hover_changed.emit(self, true)
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hovered = false
			hover_changed.emit(self, false)
			queue_redraw()
		NOTIFICATION_FOCUS_ENTER:
			focused.emit(self)
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT, NOTIFICATION_THEME_CHANGED:
			queue_redraw()


func _get_minimum_size() -> Vector2:
	return slot_size


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)

	# Background: feedback > focus > hover > normal.
	var style_name: StringName = &"normal"
	if feedback != null:
		style_name = &"accept" if feedback.ok else &"reject"
	elif has_focus():
		style_name = &"focus"
	elif _hovered:
		style_name = &"hover"
	_style(style_name).draw(get_canvas_item(), rect)
	if selected:
		_style(&"selected").draw(get_canvas_item(), rect)

	var s := stack()
	if not s.is_empty():
		var margin := float(_const(&"icon_margin", 6))
		var icon_rect := rect.grow(-margin)
		var overlay: Dictionary = {}
		for c in s.def.components:
			if c != null:
				overlay.merge(c.get_overlay_info(s))
		var tint: Color = overlay.get("tint", _color(&"icon_modulate", Color.WHITE))
		if s.def.icon != null:
			draw_texture_rect(s.def.icon, _fit(icon_rect, s.def.icon.get_size()), false, tint)
		else:
			draw_rect(icon_rect, Color(0.5, 0.5, 0.55, 0.6) * tint)

		if overlay.has("bar"):
			var bh := float(_const(&"bar_height", 3))
			var frac: float = clampf(float(overlay["bar"]), 0.0, 1.0)
			var bar_bg := Rect2(icon_rect.position.x, icon_rect.end.y - bh, icon_rect.size.x, bh)
			draw_rect(bar_bg, _color(&"bar_bg", Color(0, 0, 0, 0.6)))
			var fg := bar_bg
			fg.size.x *= frac
			var bar_col: Color = overlay.get("bar_color", _color(&"bar_fg", Color(0.35, 0.85, 0.35)))
			draw_rect(fg, bar_col)

		if s.count > 1 or not hide_single_count:
			_draw_count(rect, str(s.count))

	if container != null and container.policy != null and is_bound():
		var cap := container.policy.slot_caption(container, index, ctx)
		if cap != "":
			_draw_caption(rect, cap)

	if accepts_held and feedback == null:
		_style(&"glow").draw(get_canvas_item(), rect)


func _draw_count(rect: Rect2, text: String) -> void:
	var font := get_theme_font(&"count_font", theme_type)
	var fs := get_theme_font_size(&"count_font_size", theme_type)
	if fs <= 0:
		fs = 12
	var m := float(_const(&"count_margin", 3))
	var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs)
	var pos := Vector2(rect.end.x - m - tsize.x, rect.end.y - m - font.get_descent(fs))
	var sh := _color(&"count_shadow", Color(0, 0, 0, 0.85))
	var so := float(_const(&"count_shadow_offset", 1))
	if sh.a > 0.0:
		draw_string(font, pos + Vector2(so, so), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _color(&"count_color", Color.WHITE))


func _draw_caption(rect: Rect2, text: String) -> void:
	var font := get_theme_font(&"caption_font", theme_type)
	var fs := get_theme_font_size(&"caption_font_size", theme_type)
	if fs <= 0:
		fs = 10
	var m := float(_const(&"caption_margin", 2))
	var pos := Vector2(rect.position.x + m, rect.position.y + m + font.get_ascent(fs))
	var sh := _color(&"caption_shadow", Color(0, 0, 0, 0.85))
	if sh.a > 0.0:
		draw_string(font, pos + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _color(&"caption_color", Color(1.0, 0.9, 0.55)))


static func _fit(area: Rect2, tex_size: Vector2) -> Rect2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return area
	var scale := minf(area.size.x / tex_size.x, area.size.y / tex_size.y)
	var sz := tex_size * scale
	return Rect2(area.position + (area.size - sz) * 0.5, sz)


# ------------------------------------------------------------ theme helpers

func _style(name: StringName) -> StyleBox:
	if has_theme_stylebox(name, theme_type):
		return get_theme_stylebox(name, theme_type)
	return _fallback_style(name)


func _color(name: StringName, def: Color) -> Color:
	if has_theme_color(name, theme_type):
		return get_theme_color(name, theme_type)
	return def


func _const(name: StringName, def: int) -> int:
	if has_theme_constant(name, theme_type):
		return get_theme_constant(name, theme_type)
	return def


static func _fallback_style(name: StringName) -> StyleBox:
	if _fb_styles.is_empty():
		_fb_styles[&"normal"] = _flat(Color(0.16, 0.16, 0.19), Color(0.32, 0.32, 0.38))
		_fb_styles[&"hover"] = _flat(Color(0.21, 0.21, 0.25), Color(0.55, 0.55, 0.62))
		_fb_styles[&"focus"] = _flat(Color(0.21, 0.21, 0.25), Color(0.95, 0.85, 0.45))
		_fb_styles[&"accept"] = _flat(Color(0.18, 0.30, 0.20), Color(0.40, 0.90, 0.45))
		_fb_styles[&"reject"] = _flat(Color(0.32, 0.17, 0.17), Color(0.95, 0.35, 0.35))
		_fb_styles[&"glow"] = _flat(Color(0, 0, 0, 0), Color(0.45, 0.75, 1.0, 0.7))
		var sel := _flat(Color(0, 0, 0, 0), Color(1.0, 0.92, 0.55, 1.0))
		sel.set_border_width_all(3)
		_fb_styles[&"selected"] = sel
	return _fb_styles.get(name, _fb_styles[&"normal"])


static func _flat(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	return s
