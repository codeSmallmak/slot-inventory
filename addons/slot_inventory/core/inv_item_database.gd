@tool
class_name InvItemDatabase
extends Resource

## Registry of InvItemDefs keyed by id. Save this as a .tres manifest
## (Array of defs) rather than scanning directories at runtime — DirAccess
## on res:// sees .remap files in exports, not the original resources.

@export var items: Array[InvItemDef] = []:
	set(v):
		items = v
		_index_dirty = true

var _index: Dictionary = {}
var _index_dirty: bool = true


func _rebuild_index() -> void:
	_index.clear()
	for d in items:
		if d == null:
			continue
		if d.id == &"":
			push_warning("InvItemDatabase: item def with empty id skipped (%s)" % d.resource_path)
			continue
		if _index.has(d.id):
			push_warning("InvItemDatabase: duplicate item id '%s'" % d.id)
		_index[d.id] = d
	_index_dirty = false


func register(def: InvItemDef) -> void:
	if def == null:
		return
	if not items.has(def):
		items.append(def)
	_index_dirty = true


func has(id: StringName) -> bool:
	if _index_dirty:
		_rebuild_index()
	return _index.has(id)


func get_def(id: StringName) -> InvItemDef:
	if _index_dirty:
		_rebuild_index()
	return _index.get(id, null)


func all_ids() -> Array[StringName]:
	if _index_dirty:
		_rebuild_index()
	var out: Array[StringName] = []
	for k in _index.keys():
		out.append(k)
	return out


## Convenience: new stack of an id, or an empty stack if unknown.
func make_stack(id: StringName, count: int = 1) -> InvItemStack:
	return InvItemStack.make(get_def(id), count)
