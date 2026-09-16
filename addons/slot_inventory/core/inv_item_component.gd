@tool
class_name InvItemComponent
extends Resource

## Base class for per-instance item behaviour (durability, spoilage, fuel...).
## The component Resource itself is shared via InvItemDef; all per-stack
## state lives in `stack.data` under `data_key`, and MUST be JSON-safe
## (numbers, strings, bools, arrays/dicts of those) so save/load works.

## Key under which this component stores its state in `stack.data`.
## Subclasses should give this a unique default.
@export var data_key: StringName = &"component"


## Called when a fresh stack of this def is created. Set defaults in stack.data.
func init_data(_stack: InvItemStack) -> void:
	pass


## May `incoming` be merged into `target`? Both are non-empty, same def.
func can_merge(_target: InvItemStack, _incoming: InvItemStack) -> bool:
	return true


## Combine state when `incoming` (already validated) merges into `target`.
## Called BEFORE target.count is increased, so both counts are still the
## pre-merge values (needed for weighted averages).
func merge(_target: InvItemStack, _incoming: InvItemStack) -> void:
	pass


## `new_stack` was just split off `source`. Copy or divide state as needed.
## Called AFTER both counts are final. Default: deep-copy source state.
func split(source: InvItemStack, new_stack: InvItemStack) -> void:
	if source.data.has(data_key):
		var v: Variant = source.data[data_key]
		new_stack.data[data_key] = v.duplicate(true) if (v is Dictionary or v is Array) else v


## Time-based change. `modifier` comes from the owning container
## (fridge = 0.5, etc.). Return true if the stack changed.
func tick(_stack: InvItemStack, _delta: float, _modifier: float) -> bool:
	return false


## Data for UI overlays: e.g. {"bar": 0.75, "tint": Color(...)}. Empty = none.
func get_overlay_info(_stack: InvItemStack) -> Dictionary:
	return {}


## Tooltip lines for this component's state. Each entry is a String or a
## {"text": String, "style": StringName} Dictionary (styles: title, body,
## muted, accent, positive, negative). Empty = nothing to say.
func get_tooltip_lines(_stack: InvItemStack) -> Array:
	return []
