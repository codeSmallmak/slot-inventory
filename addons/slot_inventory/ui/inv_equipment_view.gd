@tool
class_name InvEquipmentView
extends InvSlotsView

## Paper doll. Place InvSlotView children by hand in the editor (over a body
## image, wherever you like) and NAME each child after its equip type:
## "head", "body", "hand", "ring", "ring2"... Repeated types are matched
## in child order ("ring", "ring2" -> first and second ring slot).
## bind_equipment() then wires each child to the matching equipment slot.
## Children whose name matches no slot are left unbound (with a warning).
##
## Does no layout of its own; children keep their editor positions.
## Set `group` to &"equipment" in the inspector so quick-move routes to it.

var equipment: InvEquipment = null


func bind(c: InvContainer) -> void:
	# Equipment slots are keyed by type, so binding a bare container maps
	# children to slots in child order.
	container = c
	_collect_children()
	for i in _views.size():
		_views[i].bind(c, i if c != null and i < c.size() else -1)
	rebuilt.emit()


func bind_equipment(e: InvEquipment) -> void:
	equipment = e
	container = e.container if e != null else null
	_collect_children()
	if e == null:
		for v in _views:
			v.unbind()
		rebuilt.emit()
		return
	var used: Dictionary = {}
	for v in _views:
		var t := _type_from_name(v.name)
		var nth: int = used.get(t, 0)
		var idx := e.slot_for(t, nth)
		if idx == -1:
			push_warning("InvEquipmentView: no equipment slot for child '%s' (type '%s')" % [v.name, t])
			v.unbind()
			continue
		used[t] = nth + 1
		v.bind(e.container, idx)
	rebuilt.emit()


## Slot view showing `slot_type`, or null.
func view_for(slot_type: StringName, nth: int = 0) -> InvSlotView:
	if equipment == null:
		return null
	var idx := equipment.slot_for(slot_type, nth)
	for v in _views:
		if v.index == idx:
			return v
	return null


func _collect_children() -> void:
	for v in _views:
		if v.slot_input.is_connected(_on_slot_input):
			v.slot_input.disconnect(_on_slot_input)
			v.hover_changed.disconnect(_on_slot_hover)
			v.focused.disconnect(_on_slot_focused)
	_views.clear()
	for ch in get_children():
		if ch is InvSlotView:
			_views.append(ch)
			_wire(ch)


## "ring2" -> &"ring"; "Head" -> &"head".
static func _type_from_name(n: String) -> StringName:
	var s := n.to_lower()
	while s.length() > 1 and s[s.length() - 1].is_valid_int():
		s = s.left(s.length() - 1)
	return StringName(s)
