@tool
extends EditorPlugin

## Editor integration for Slot Inventory. The addon works without this
## plugin being enabled (all classes use class_name); enabling it adds:
##   Project > Tools > Slot Inventory: Bake Icons from Models
## which renders every model under res://models to res://icons (see
## docs/02_items_and_icons.md to change paths, size or angle).

const TOOL_BAKE := "Slot Inventory: Bake Icons from Models"


func _enter_tree() -> void:
	add_tool_menu_item(TOOL_BAKE, _bake_icons)


func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_BAKE)


func _bake_icons() -> void:
	var script := load("res://addons/slot_inventory/tools/bake_icons.gd") as GDScript
	if script == null:
		push_error("Slot Inventory: tools/bake_icons.gd not found")
		return
	var runner: EditorScript = script.new()
	runner._run()
