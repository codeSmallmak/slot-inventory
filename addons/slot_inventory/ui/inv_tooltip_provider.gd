@tool
class_name InvTooltipProvider
extends Resource

## Decides WHAT a tooltip says: an ordered list of InvTooltipFields. Save one
## as a .tres, drop it on the InvTooltipView, and edit the list in the
## inspector — each game (or each screen) can show different data without
## touching code. build() returns styled lines; the view renders them.

@export var fields: Array[InvTooltipField] = []
## Drop repeated blank lines and blank lines at either end.
@export var collapse_separators: bool = true


## Sensible default: name, description, component info (durability...),
## shop/sell prices when the slot's policy has them, and the tags in muted
## text at the bottom.
static func default_provider() -> InvTooltipProvider:
	var p := InvTooltipProvider.new()
	p.fields = [
		InvTooltipField.make(InvTooltipField.Kind.NAME, InvTooltipField.STYLE_TITLE),
		InvTooltipField.make(InvTooltipField.Kind.DESCRIPTION, InvTooltipField.STYLE_MUTED),
		InvTooltipField.make(InvTooltipField.Kind.COMPONENTS, InvTooltipField.STYLE_BODY),
		InvTooltipField.make(InvTooltipField.Kind.POLICY, InvTooltipField.STYLE_ACCENT),
		InvTooltipField.make(InvTooltipField.Kind.SEPARATOR),
		InvTooltipField.make(InvTooltipField.Kind.TAGS, InvTooltipField.STYLE_MUTED),
	]
	return p


func build(stack: InvItemStack, container: InvContainer = null, index: int = -1, ctx: InvTransferContext = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in fields:
		if f == null:
			continue
		out.append_array(f.lines(stack, container, index, ctx))
	if collapse_separators:
		out = _collapse(out)
	return out


## Plain-text form (one line per entry). Handy for tests and logging.
func build_text(stack: InvItemStack, container: InvContainer = null, index: int = -1, ctx: InvTransferContext = null) -> String:
	var parts: Array[String] = []
	for l in build(stack, container, index, ctx):
		parts.append(str(l["text"]))
	return "\n".join(parts)


static func _collapse(lines: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in lines:
		var blank: bool = str(l["text"]) == ""
		if blank and (out.is_empty() or str(out[-1]["text"]) == ""):
			continue
		out.append(l)
	while not out.is_empty() and str(out[-1]["text"]) == "":
		out.pop_back()
	return out
