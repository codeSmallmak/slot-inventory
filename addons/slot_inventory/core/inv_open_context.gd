@tool
class_name InvOpenContext
extends RefCounted

## The set of containers currently visible to the player, in open order,
## each tagged with a group (&"player", &"external", &"equipment", ...).
## Owns the routing rules for quick-move (shift-click) and the scope for
## collect (double-click). Nothing here touches the scene tree; the UI
## calls open()/close() as screens appear and disappear.
##
## Quick-move routing, in priority order:
##   1. explicit route: set_route(from_group, [to_group, ...])
##   2. every open container in a DIFFERENT group, in open order
##   3. every OTHER open container in the SAME group (e.g. inventory <-> hotbar
##      when nothing external is open)

signal container_opened(container: InvContainer, group: StringName)
signal container_closed(container: InvContainer, group: StringName)

const DEFAULT_GROUP := &"player"

var _containers: Array[InvContainer] = []
var _groups: Array[StringName] = []
## from_group -> Array[StringName] of target groups, in priority order.
var _routes: Dictionary = {}


# ------------------------------------------------------------- open / close

func open(c: InvContainer, group: StringName = DEFAULT_GROUP) -> void:
	if c == null:
		return
	var at := _containers.find(c)
	if at != -1:
		_groups[at] = group
		return
	_containers.append(c)
	_groups.append(group)
	container_opened.emit(c, group)


func close(c: InvContainer) -> void:
	var at := _containers.find(c)
	if at == -1:
		return
	var g := _groups[at]
	_containers.remove_at(at)
	_groups.remove_at(at)
	container_closed.emit(c, g)


## Close every container in `group` (or all when group is empty).
func close_group(group: StringName = &"") -> void:
	for i in range(_containers.size() - 1, -1, -1):
		if group == &"" or _groups[i] == group:
			close(_containers[i])


func is_open(c: InvContainer) -> bool:
	return _containers.has(c)


func group_of(c: InvContainer) -> StringName:
	var at := _containers.find(c)
	return _groups[at] if at != -1 else &""


func containers() -> Array[InvContainer]:
	return _containers.duplicate()


func containers_in(group: StringName) -> Array[InvContainer]:
	var out: Array[InvContainer] = []
	for i in _containers.size():
		if _groups[i] == group:
			out.append(_containers[i])
	return out


func size() -> int:
	return _containers.size()


# ------------------------------------------------------------------ routing

func set_route(from_group: StringName, to_groups: Array) -> void:
	var g: Array[StringName] = []
	for x in to_groups:
		g.append(x)
	_routes[from_group] = g


func clear_route(from_group: StringName) -> void:
	_routes.erase(from_group)


## Ordered list of containers a quick-move out of `from` should try.
func quick_move_targets(from: InvContainer) -> Array[InvContainer]:
	var out: Array[InvContainer] = []
	var fg := group_of(from)
	if _routes.has(fg):
		for tg in _routes[fg]:
			for c in containers_in(tg):
				if c != from:
					out.append(c)
		return out
	for i in _containers.size():
		if _groups[i] != fg and _containers[i] != from:
			out.append(_containers[i])
	if out.is_empty():
		for i in _containers.size():
			if _groups[i] == fg and _containers[i] != from:
				out.append(_containers[i])
	return out


# --------------------------------------------------------------- operations

## Shift-click: move `amount` (default all) of from[i] into the routed
## targets, stopping when everything moved. Target order within the route:
##   1. containers already holding a mergeable stack with room (merge pass)
##   2. containers with a slot FILTER that accepts the item (specialised
##      storage: toolbox, equipment, seed bag) — first-fit
##   3. everything else — first-fit
## Summary result: ok if anything moved; to/to_index = last slot filled.
func quick_move(from: InvContainer, i: int, amount: int = -1, ctx: InvTransferContext = null) -> InvTransferResult:
	if from == null or not from.is_valid_index(i):
		return InvTransferResult.failure(InvDropCheck.INVALID_INDEX, from, i, null, -1)
	var src := from.get_stack(i)
	if src.is_empty():
		return InvTransferResult.failure(InvDropCheck.EMPTY, from, i, null, -1)
	if amount < 0 or amount > src.count:
		amount = src.count

	var summary := InvTransferResult.new()
	summary.from = from
	summary.from_index = i
	summary.to_index = -1
	summary.def = src.def
	var last_hint: StringName = InvDropCheck.FULL

	var targets := quick_move_targets(from)
	var ordered: Array[InvContainer] = []
	var passes: Array = []  # [container, merge_only]
	for t in targets:
		if t.has_mergeable_room(src):
			passes.append([t, true])
	for t in targets:
		if t.has_filter_accepting(src):
			ordered.append(t)
	for t in targets:
		if not ordered.has(t):
			ordered.append(t)
	for t in ordered:
		passes.append([t, false])

	for p in passes:
		if amount <= 0 or src.is_empty():
			break
		var to: InvContainer = p[0]
		var r := InvTransfer.move_auto(from, i, to, amount, ctx, p[1])
		if r.ok:
			summary.ok = true
			summary.hint = r.hint
			summary.moved_count += r.moved_count
			summary.to = to
			summary.to_index = r.to_index
			amount -= r.moved_count
		else:
			last_hint = r.hint
	summary.remainder = amount
	if not summary.ok:
		summary.hint = last_hint
	return summary


## Double-click: gather everything mergeable with the held stack from every
## open container. Returns units gathered.
func collect(held: InvHeldStack, ctx: InvTransferContext = null) -> int:
	if held == null:
		return 0
	return held.collect(_containers, ctx)


func _to_string() -> String:
	return "InvOpenContext(%d open)" % _containers.size()
