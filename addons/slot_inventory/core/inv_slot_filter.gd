@tool
class_name InvSlotFilter
extends Resource

## Per-slot acceptance rule based on the item def. Empty stacks always pass
## (a filter restricts what may enter, never whether a slot may be emptied).

## Item must carry ALL of these tags.
@export var required_tags: Array[StringName] = []
## Item must carry NONE of these tags.
@export var blocked_tags: Array[StringName] = []
## If non-empty, item.equip_type must equal this.
@export var equip_type: StringName = &""
## If non-empty, only these exact item ids are accepted.
@export var allowed_ids: Array[StringName] = []


func accepts(stack: InvItemStack) -> InvDropCheck:
	if stack == null or stack.is_empty():
		return InvDropCheck.accept()
	var def: InvItemDef = stack.def
	if not allowed_ids.is_empty() and not allowed_ids.has(def.id):
		return InvDropCheck.reject(InvDropCheck.WRONG_TYPE)
	if equip_type != &"" and def.equip_type != equip_type:
		return InvDropCheck.reject(InvDropCheck.WRONG_TYPE)
	if not def.has_all_tags(required_tags):
		return InvDropCheck.reject(InvDropCheck.WRONG_TYPE)
	if def.has_any_tag(blocked_tags):
		return InvDropCheck.reject(InvDropCheck.WRONG_TYPE)
	return InvDropCheck.accept()
