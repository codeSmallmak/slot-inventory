@tool
class_name InvTooltipView
extends PanelContainer

## Renders the lines an InvTooltipProvider produces for the hovered slot.
## Positioned beside the slot (not the mouse, so it doesn't jitter) and
## clamped to the viewport. The InvUISession shows/hides it; you can also
## drive it yourself with show_for() / hide_tip().
##
## Theming (type "InvTooltipView"):
##   styles:      panel
##   colors:      title_color, body_color, muted_color, accent_color,
##                positive_color, negative_color
##   font_sizes:  title_font_size, body_font_size, muted_font_size
##   constants:   max_width, slot_gap

@export var provider: InvTooltipProvider = null
@export var theme_type: StringName = &"InvTooltipView"
## Fallback when the theme has no max_width constant.
@export var max_width: int = 260

var _label: RichTextLabel
var _view: InvSlotView = null
var _ctx: InvTransferContext = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 90
	visible = false
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _ready() -> void:
	if has_theme_stylebox(&"panel", theme_type):
		add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", theme_type))


## Build and show the tooltip for `view`'s slot. Hides if there is nothing
## to say (empty slot, provider produced no lines).
func show_for(view: InvSlotView, ctx: InvTransferContext = null) -> void:
	_unwatch()
	_view = view
	_ctx = ctx
	if not refresh():
		return
	_watch()
	visible = true
	_reposition()


func hide_tip() -> void:
	_unwatch()
	_view = null
	visible = false


func is_showing_for(view: InvSlotView) -> bool:
	return visible and _view == view


## Rebuild text from the current slot contents. Returns false (and hides)
## when there is nothing to show.
func refresh() -> bool:
	if _view == null or not is_instance_valid(_view) or not _view.is_bound():
		visible = false
		return false
	var p := provider if provider != null else InvTooltipProvider.default_provider()
	var lines := p.build(_view.stack(), _view.container, _view.index, _ctx)
	if lines.is_empty():
		visible = false
		return false
	var w := get_theme_constant(&"max_width", theme_type) if has_theme_constant(&"max_width", theme_type) else max_width
	var inner_max := maxf(w - _panel_margins().x, 40.0)
	# Measure the natural (unwrapped) width, then wrap only if it exceeds
	# the cap. fit_content needs a width to compute its height from.
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size = Vector2.ZERO
	_label.text = to_bbcode(lines)
	var natural := float(_label.get_content_width())
	if natural > inner_max:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size.x = inner_max
	else:
		_label.custom_minimum_size.x = natural
	reset_size()
	if is_inside_tree():
		# Container layout settles next frame; nudge the position after it.
		_reposition.call_deferred()
	return true


## Lines -> BBCode using the theme's colors and sizes.
func to_bbcode(lines: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for l in lines:
		var text: String = str(l.get("text", ""))
		var style: StringName = l.get("style", InvTooltipField.STYLE_BODY)
		if text == "":
			parts.append("")
			continue
		var col := _style_color(style)
		var fs := _style_size(style)
		parts.append("[font_size=%d][color=#%s]%s[/color][/font_size]" % [fs, col.to_html(true), _escape(text)])
	return "\n".join(parts)


func _style_color(style: StringName) -> Color:
	var name := StringName(String(style) + "_color")
	if has_theme_color(name, theme_type):
		return get_theme_color(name, theme_type)
	match style:
		InvTooltipField.STYLE_TITLE: return Color(1.0, 0.95, 0.8)
		InvTooltipField.STYLE_MUTED: return Color(0.7, 0.7, 0.75)
		InvTooltipField.STYLE_ACCENT: return Color(1.0, 0.9, 0.55)
		InvTooltipField.STYLE_POSITIVE: return Color(0.55, 0.9, 0.55)
		InvTooltipField.STYLE_NEGATIVE: return Color(0.95, 0.45, 0.45)
	return Color(0.92, 0.92, 0.94)


func _style_size(style: StringName) -> int:
	var name: StringName = &"body_font_size"
	match style:
		InvTooltipField.STYLE_TITLE: name = &"title_font_size"
		InvTooltipField.STYLE_MUTED: name = &"muted_font_size"
	if has_theme_font_size(name, theme_type):
		return get_theme_font_size(name, theme_type)
	match style:
		InvTooltipField.STYLE_TITLE: return 15
		InvTooltipField.STYLE_MUTED: return 11
	return 13


static func _escape(t: String) -> String:
	return t.replace("[", "[lb]")


# ------------------------------------------------------------- positioning

func _reposition() -> void:
	if _view == null or not is_inside_tree():
		return
	var gap := float(get_theme_constant(&"slot_gap", theme_type)) if has_theme_constant(&"slot_gap", theme_type) else 6.0
	var r := _view.get_global_rect()
	var vp := get_viewport_rect()
	var pos := Vector2(r.end.x + gap, r.position.y)
	if pos.x + size.x > vp.end.x:
		pos.x = r.position.x - gap - size.x
	if pos.x < vp.position.x:
		pos.x = vp.position.x
	if pos.y + size.y > vp.end.y:
		pos.y = vp.end.y - size.y
	if pos.y < vp.position.y:
		pos.y = vp.position.y
	global_position = pos


func _panel_margins() -> Vector2:
	var sb := get_theme_stylebox(&"panel")
	if sb == null:
		return Vector2.ZERO
	return Vector2(sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM))


# ------------------------------------------------------------- live update

func _watch() -> void:
	if _view != null and _view.container != null and not _view.container.slot_changed.is_connected(_on_slot_changed):
		_view.container.slot_changed.connect(_on_slot_changed)


func _unwatch() -> void:
	if _view != null and is_instance_valid(_view) and _view.container != null \
			and _view.container.slot_changed.is_connected(_on_slot_changed):
		_view.container.slot_changed.disconnect(_on_slot_changed)


func _on_slot_changed(i: int) -> void:
	if _view != null and i == _view.index:
		if refresh():
			_reposition()
		else:
			_unwatch()
