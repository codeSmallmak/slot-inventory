@tool
class_name InvEquipment
extends RefCounted

## Paper-doll equipment: an InvContainer with one slot per equip type, each
## slot filtered to that type and capped at one item. Movement still goes
## through InvTransfer (so it works with the cursor, quick-move and swaps);
## this class adds type-keyed lookup, equip/unequip helpers and signals.

signal equipped(slot_type: StringName, def: InvItemDef)
signal unequipped(slot_type: StringName, def: InvItemDef)

var container: InvContainer
var slot_types: Array[StringName] = []

var _prev: Array[InvItemDef] = []


## `types` may repeat (two ring slots): slot_for(type, n) picks the nth.
func _init(types: Array = [], id: StringName = &"equipment") -> void:
	for t in types:
		slot_types.append(t)
	container = InvContainer.new(slot_types.size(), id)
	for i in slot_types.size():
		var f := InvSlotFilter.new()
		f.equip_type = slot_types[i]
		container.set_filter(i, f)
		container.set_slot_max(i, 1)
		_prev.append(null)
	container.slot_changed.connect(_on_slot_changed)


func size() -> int:
	return slot_types.size()


## Index of the nth slot of `slot_type`, or -1.
func slot_for(slot_type: StringName, nth: int = 0) -> int:
	var seen := 0
	for i in slot_types.size():
		if slot_types[i] == slot_type:
			if seen == nth:
				return i
			seen += 1
	return -1


func type_of(index: int) -> StringName:
	return slot_types[index] if index >= 0 and index < slot_types.size() else &""


## Equipped stack for a type (empty stack if none / unknown type).
func get_equipped(slot_type: StringName, nth: int = 0) -> InvItemStack:
	var i := slot_for(slot_type, nth)
	return container.get_stack(i) if i != -1 else InvItemStack.new()


func get_equipped_def(slot_type: StringName, nth: int = 0) -> InvItemDef:
	return get_equipped(slot_type, nth).def


func is_equipped(slot_type: StringName, nth: int = 0) -> bool:
	return not get_equipped(slot_type, nth).is_empty()


## All equipped defs, keyed by slot index.
func equipped_defs() -> Dictionary:
	var out := {}
	for i in slot_types.size():
		var s := container.get_stack(i)
		if not s.is_empty():
			out[i] = s.def
	return out


## Move from[i] into the matching equipment slot (first empty slot of that
## type, else the first one — a swap). Fails with WRONG_TYPE if the item has
## no equip_type or no slot exists for it.
func equip(from: InvContainer, i: int, ctx: InvTransferContext = null) -> InvTransferResult:
	if from == null or not from.is_valid_index(i):
		return InvTransferResult.failure(InvDropCheck.INVALID_INDEX, from, i, container, -1)
	var s := from.get_stack(i)
	if s.is_empty():
		return InvTransferResult.failure(InvDropCheck.EMPTY, from, i, container, -1)
	var target := _target_slot(s.def)
	if target == -1:
		return InvTransferResult.failure(InvDropCheck.WRONG_TYPE, from, i, container, -1)
	return InvTransfer.move(from, i, container, target, 1, ctx)


## Move the item in `slot_type` into `to` (first fit).
func unequip(slot_type: StringName, to: InvContainer, ctx: InvTransferContext = null, nth: int = 0) -> InvTransferResult:
	var i := slot_for(slot_type, nth)
	if i == -1:
		return InvTransferResult.failure(InvDropCheck.INVALID_INDEX, container, -1, to, -1)
	return InvTransfer.move_auto(container, i, to, -1, ctx)


## Would `def` fit somewhere here (ignoring occupancy)?
func accepts_def(def: InvItemDef) -> bool:
	return def != null and def.is_equippable() and slot_for(def.equip_type) != -1


func _target_slot(def: InvItemDef) -> int:
	if def == null or not def.is_equippable():
		return -1
	var first := -1
	for i in slot_types.size():
		if slot_types[i] != def.equip_type:
			continue
		if first == -1:
			first = i
		if container.is_slot_empty(i):
			return i
	return first


func _on_slot_changed(i: int) -> void:
	var now := container.get_stack(i).def
	var before := _prev[i]
	if now == before:
		return
	_prev[i] = now
	if before != null:
		unequipped.emit(slot_types[i], before)
	if now != null:
		equipped.emit(slot_types[i], now)
