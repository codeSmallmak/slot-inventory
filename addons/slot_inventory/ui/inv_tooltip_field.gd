@tool
class_name InvTooltipField
extends Resource

## One line (or block) of an item tooltip. An InvTooltipProvider holds an
## ordered list of these; reorder, remove or restyle them in the inspector
## to decide what a tooltip shows. Subclass and override lines() for
## game-specific data (quality stars, quest markers...).
##
## Each produced line is a Dictionary: {"text": String, "style": StringName}
## where style is one of title / body / muted / accent / positive / negative
## (the InvTooltipView maps styles to theme colors and font sizes).

enum Kind {
	NAME,          ## def.display_name (falls back to id)
	DESCRIPTION,   ## def.description
	COUNT,         ## stack count, e.g. "x12"
	MAX_STACK,     ## "12 / 50"
	TAGS,          ## def.tags joined with ", "
	EQUIP_TYPE,    ## def.equip_type
	PRICE,         ## def.price
	SELL_PRICE,    ## def.sell_price
	ID,            ## def.id
	COMPONENTS,    ## every component's get_tooltip_lines(stack)
	POLICY,        ## container.policy.slot_tooltip_lines(...) (shop prices etc.)
	SEPARATOR,     ## a blank line
	CUSTOM,        ## subclass hook: override lines()
}

const STYLE_TITLE := &"title"
const STYLE_BODY := &"body"
const STYLE_MUTED := &"muted"
const STYLE_ACCENT := &"accent"
const STYLE_POSITIVE := &"positive"
const STYLE_NEGATIVE := &"negative"

@export var kind: Kind = Kind.NAME
## Text placed before the value ("Sell: ").
@export var label: String = ""
## printf-style format applied to the value; %s for text kinds, %d for
## numeric ones (COUNT, PRICE, SELL_PRICE). MAX_STACK uses "%d / %d".
@export var format: String = ""
@export var style: StringName = STYLE_BODY
## Skip the line when the value is empty / zero.
@export var hide_if_empty: bool = true
## Show this field only when the container has a policy of this class name
## (e.g. "InvShopPolicy"). Empty = always.
@export var only_with_policy: String = ""


static func make(p_kind: Kind, p_style: StringName = STYLE_BODY, p_label: String = "", p_format: String = "") -> InvTooltipField:
	var f := InvTooltipField.new()
	f.kind = p_kind
	f.style = p_style
	f.label = p_label
	f.format = p_format
	return f


func lines(stack: InvItemStack, container: InvContainer, index: int, ctx: InvTransferContext) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if only_with_policy != "":
		if container == null or container.policy == null:
			return out
		var s: Script = container.policy.get_script()
		var matched := false
		while s != null:
			if s.get_global_name() == StringName(only_with_policy):
				matched = true
				break
			s = s.get_base_script()
		if not matched:
			return out
	if kind == Kind.SEPARATOR:
		out.append(_line("", style))
		return out
	if stack == null or stack.is_empty():
		return out
	var d := stack.def
	match kind:
		Kind.NAME:
			_push_text(out, d.display_name if d.display_name != "" else String(d.id))
		Kind.DESCRIPTION:
			_push_text(out, d.description)
		Kind.COUNT:
			_push_int(out, stack.count, "x%d")
		Kind.MAX_STACK:
			var fmt := format if format != "" else "%d / %d"
			out.append(_line(label + fmt % [stack.count, d.max_stack], style))
		Kind.TAGS:
			var parts: Array[String] = []
			for t in d.tags:
				parts.append(String(t))
			_push_text(out, ", ".join(parts))
		Kind.EQUIP_TYPE:
			_push_text(out, String(d.equip_type))
		Kind.PRICE:
			_push_int(out, d.price, "%dg")
		Kind.SELL_PRICE:
			_push_int(out, d.sell_price, "%dg")
		Kind.ID:
			_push_text(out, String(d.id))
		Kind.COMPONENTS:
			for c in d.components:
				if c == null:
					continue
				for l in c.get_tooltip_lines(stack):
					out.append(_normalise(l))
		Kind.POLICY:
			if container != null and container.policy != null:
				for l in container.policy.slot_tooltip_lines(container, index, ctx):
					out.append(_normalise(l))
		Kind.CUSTOM:
			pass  # subclasses override lines()
	return out


func _push_text(out: Array[Dictionary], value: String) -> void:
	if value == "" and hide_if_empty:
		return
	var fmt := format if format != "" else "%s"
	out.append(_line(label + fmt % value, style))


func _push_int(out: Array[Dictionary], value: int, default_fmt: String) -> void:
	if value == 0 and hide_if_empty:
		return
	var fmt := format if format != "" else default_fmt
	out.append(_line(label + fmt % value, style))


## Accepts a String or a {"text","style"} Dictionary from hooks.
func _normalise(l: Variant) -> Dictionary:
	if l is Dictionary:
		var d: Dictionary = l
		return _line(str(d.get("text", "")), d.get("style", style))
	return _line(str(l), style)


static func _line(text: String, p_style: StringName) -> Dictionary:
	return {"text": text, "style": p_style}
