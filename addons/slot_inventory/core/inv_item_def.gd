@tool
class_name InvItemDef
extends Resource

## Static, shared item definition. Never holds per-instance state.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export_range(1, 99999) var max_stack: int = 1
## Free-form classification: &"tool", &"seed", &"food", &"sellable" ...
@export var tags: Array[StringName] = []
## &"" = not equippable. Otherwise the slot type it fits: &"head", &"hand" ...
@export var equip_type: StringName = &""
@export var price: int = 0
@export var sell_price: int = 0
@export var components: Array[InvItemComponent] = []


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func has_any_tag(list: Array) -> bool:
	for t in list:
		if tags.has(t):
			return true
	return false


func has_all_tags(list: Array) -> bool:
	for t in list:
		if not tags.has(t):
			return false
	return true


func is_equippable() -> bool:
	return equip_type != &""


## First component whose script is (or extends) `script`. Null if none.
func get_component(script: Script) -> InvItemComponent:
	for c in components:
		if c == null:
			continue
		var s: Script = c.get_script()
		while s != null:
			if s == script:
				return c
			s = s.get_base_script()
	return null


func _to_string() -> String:
	return "InvItemDef(%s)" % id
