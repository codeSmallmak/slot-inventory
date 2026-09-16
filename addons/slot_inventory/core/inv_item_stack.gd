@tool
class_name InvItemStack
extends RefCounted

## Per-instance item state: a def, a count, and a component-state dictionary.
## A container slot ALWAYS holds an InvItemStack (never null); an empty slot
## is a stack with def == null or count == 0.

var def: InvItemDef = null
var count: int = 0
## Component state. Keys are component data_keys; values must be JSON-safe.
var data: Dictionary = {}


## Create a stack of `p_count` and let each component initialise its state.
static func make(p_def: InvItemDef, p_count: int = 1) -> InvItemStack:
	var s := InvItemStack.new()
	if p_def == null or p_count <= 0:
		return s
	s.def = p_def
	s.count = p_count
	for c in p_def.components:
		if c != null:
			c.init_data(s)
	return s


static func empty() -> InvItemStack:
	return InvItemStack.new()


func is_empty() -> bool:
	return def == null or count <= 0


func clear() -> void:
	def = null
	count = 0
	data = {}


func max_stack() -> int:
	return def.max_stack if def != null else 0


## Same def, both non-empty, and every component agrees `other` may merge in.
func can_merge_with(other: InvItemStack) -> bool:
	if other == null or is_empty() or other.is_empty():
		return false
	if def != other.def:
		return false
	for c in def.components:
		if c != null and not c.can_merge(self, other):
			return false
	return true


## Deep copy (def is shared, data is duplicated).
func duplicate_stack() -> InvItemStack:
	var s := InvItemStack.new()
	s.def = def
	s.count = count
	s.data = data.duplicate(true)
	return s


## Remove `n` units from this stack and return them as a new stack, running
## component split hooks. n is clamped to [0, count].
func split_off(n: int) -> InvItemStack:
	n = clampi(n, 0, count)
	var out := InvItemStack.new()
	if n == 0:
		return out
	out.def = def
	out.count = n
	count -= n
	for c in def.components:
		if c != null:
			c.split(self, out)
	if count <= 0:
		clear()
	return out


## Merge ALL of `incoming` into this stack, running component merge hooks.
## Caller must have validated with can_merge_with() and capacity.
## Leaves `incoming` empty.
func absorb(incoming: InvItemStack) -> void:
	for c in def.components:
		if c != null:
			c.merge(self, incoming)
	count += incoming.count
	incoming.clear()


## Serialisation. Component data must already be JSON-safe.
func to_dict() -> Dictionary:
	if is_empty():
		return {}
	return {
		"id": String(def.id),
		"count": count,
		"data": data.duplicate(true),
	}


static func from_dict(d: Dictionary, db: InvItemDatabase) -> InvItemStack:
	var s := InvItemStack.new()
	if d.is_empty() or db == null:
		return s
	var p_def: InvItemDef = db.get_def(StringName(str(d.get("id", ""))))
	if p_def == null:
		push_warning("InvItemStack.from_dict: unknown item id '%s'" % str(d.get("id", "")))
		return s
	s.def = p_def
	s.count = int(d.get("count", 0))
	var raw: Variant = d.get("data", {})
	s.data = raw.duplicate(true) if raw is Dictionary else {}
	if s.count <= 0:
		s.clear()
	return s


func _to_string() -> String:
	if is_empty():
		return "InvItemStack(empty)"
	return "InvItemStack(%s x%d)" % [def.id, count]
