@tool
class_name InvContainer
extends RefCounted

## A fixed-size list of slots. Owns item data; UI observes via signals.
## Slots ALWAYS hold an InvItemStack (never null). Empty = stack.is_empty().
##
## Rules live here (filters, per-slot caps, policy). Movement between
## containers goes through InvTransfer so every path is validated the same
## way. Direct mutation methods (set_stack, notify_slot_mutated) exist for
## InvTransfer and for game code that deliberately bypasses rules (loot
## generation, debug); they still emit signals.

signal slot_changed(index: int)
signal item_added(def: InvItemDef, count: int)
signal item_removed(def: InvItemDef, count: int)
signal transaction_committed(result: InvTransferResult)

var id: StringName = &""
var policy: InvContainerPolicy = null
## Multiplier handed to component tick() (fridge = 0.5, compost = 2.0).
var tick_modifier: float = 1.0

var _slots: Array[InvItemStack] = []
var _filters: Array[InvSlotFilter] = []
## Per-slot cap override. 0 = use def.max_stack.
var _slot_max: Array[int] = []


func _init(p_size: int = 0, p_id: StringName = &"") -> void:
	id = p_id
	resize(p_size)


# ---------------------------------------------------------------- structure

func resize(n: int) -> void:
	n = maxi(n, 0)
	var old := _slots.size()
	_slots.resize(n)
	_filters.resize(n)
	_slot_max.resize(n)
	for i in range(old, n):
		_slots[i] = InvItemStack.new()
		_filters[i] = null
		_slot_max[i] = 0


func size() -> int:
	return _slots.size()


func is_valid_index(i: int) -> bool:
	return i >= 0 and i < _slots.size()


## Live stack reference. Treat as read-only outside InvTransfer.
func get_stack(i: int) -> InvItemStack:
	return _slots[i]


func is_slot_empty(i: int) -> bool:
	return _slots[i].is_empty()


func set_filter(i: int, f: InvSlotFilter) -> void:
	_filters[i] = f


func get_filter(i: int) -> InvSlotFilter:
	return _filters[i]


func set_all_filters(f: InvSlotFilter) -> void:
	for i in _filters.size():
		_filters[i] = f


func set_slot_max(i: int, m: int) -> void:
	_slot_max[i] = maxi(m, 0)


func set_all_slot_max(m: int) -> void:
	for i in _slot_max.size():
		_slot_max[i] = maxi(m, 0)


func get_slot_max(i: int) -> int:
	return _slot_max[i]


## Effective cap for `def` in slot i: min(def.max_stack, slot override).
func effective_max(i: int, def: InvItemDef) -> int:
	if def == null:
		return 0
	var m := def.max_stack
	if _slot_max[i] > 0:
		m = mini(m, _slot_max[i])
	return m


# ------------------------------------------------------------------- checks

## Can `stack` (all of it, or as much as fits) enter slot i?
## Positive hints: PLACE (empty), MERGE (same mergeable item), SWAP (other
## item occupies the slot but the filter/policy accept the incoming one).
## `capacity` = units that would fit for PLACE/MERGE; for SWAP it is the
## slot cap for the incoming def (InvTransfer requires the whole stack fit).
func check_insert(i: int, stack: InvItemStack, ctx: InvTransferContext = null) -> InvDropCheck:
	if not is_valid_index(i):
		return InvDropCheck.reject(InvDropCheck.INVALID_INDEX)
	if stack == null or stack.is_empty():
		return InvDropCheck.reject(InvDropCheck.EMPTY)
	if _filters[i] != null:
		var fc := _filters[i].accepts(stack)
		if not fc.ok:
			return fc
	var policy_hint: StringName = &""
	if policy != null:
		var pc := policy.can_insert(self, i, stack, ctx)
		if not pc.ok:
			return pc
		if pc.hint != InvDropCheck.PLACE:
			policy_hint = pc.hint
	var cur := _slots[i]
	var cap := effective_max(i, stack.def)
	if cur.is_empty():
		return InvDropCheck.accept(policy_hint if policy_hint != &"" else InvDropCheck.PLACE, mini(cap, stack.count))
	if cur.can_merge_with(stack):
		var room := cap - cur.count
		if room <= 0:
			return InvDropCheck.reject(InvDropCheck.FULL)
		return InvDropCheck.accept(policy_hint if policy_hint != &"" else InvDropCheck.MERGE, mini(room, stack.count))
	return InvDropCheck.accept(policy_hint if policy_hint != &"" else InvDropCheck.SWAP, cap)


## Can `amount` units leave slot i? capacity = units actually removable.
func check_remove(i: int, amount: int, ctx: InvTransferContext = null) -> InvDropCheck:
	if not is_valid_index(i):
		return InvDropCheck.reject(InvDropCheck.INVALID_INDEX)
	var cur := _slots[i]
	if cur.is_empty():
		return InvDropCheck.reject(InvDropCheck.EMPTY)
	amount = clampi(amount, 0, cur.count)
	if amount <= 0:
		return InvDropCheck.reject(InvDropCheck.NOOP)
	var hint: StringName = InvDropCheck.PLACE
	if policy != null:
		var pc := policy.can_remove(self, i, amount, ctx)
		if not pc.ok:
			return pc
		# Policies may cap the amount (funds) and relabel it (BUY).
		if pc.capacity > 0:
			amount = mini(amount, pc.capacity)
		if pc.hint != InvDropCheck.PLACE:
			hint = pc.hint
	return InvDropCheck.accept(hint, amount)


## True if at least one slot could take one unit of `stack` right now
## without a swap. (Used for the accepts_held glow; cache per held change.)
func can_accept_any(stack: InvItemStack, ctx: InvTransferContext = null) -> bool:
	for i in _slots.size():
		var c := check_insert(i, stack, ctx)
		if c.ok and c.hint != InvDropCheck.SWAP and c.capacity > 0:
			return true
	return false


## True if some slot already holds a stack `stack` could merge into with
## room to spare. (Quick-move uses this to prefer merge targets.)
func has_mergeable_room(stack: InvItemStack, ctx: InvTransferContext = null) -> bool:
	if stack == null or stack.is_empty():
		return false
	for i in _slots.size():
		if _slots[i].is_empty():
			continue
		var c := check_insert(i, stack, ctx)
		if c.ok and c.hint == InvDropCheck.MERGE and c.capacity > 0:
			return true
	return false


## True if some slot carries a non-null filter that accepts `stack`.
## Marks this container as "specialised storage" for the item.
func has_filter_accepting(stack: InvItemStack) -> bool:
	if stack == null or stack.is_empty():
		return false
	for f in _filters:
		if f != null and f.accepts(stack).ok:
			return true
	return false


# ---------------------------------------------------------------- mutation

## Replace the contents of slot i. Emits deltas + slot_changed.
func set_stack(i: int, stack: InvItemStack) -> void:
	var old := _slots[i]
	var new_stack := stack if stack != null else InvItemStack.new()
	_slots[i] = new_stack
	_emit_delta(old.def, old.count, new_stack.def, new_stack.count)
	slot_changed.emit(i)


## Call after mutating a slot's stack in place (absorb/split_off), passing
## the def/count it had before. Emits deltas + slot_changed.
func notify_slot_mutated(i: int, old_def: InvItemDef, old_count: int) -> void:
	var cur := _slots[i]
	_emit_delta(old_def, old_count, cur.def, cur.count)
	slot_changed.emit(i)


## Call after changing a stack's `data` in place (water level, charge...).
## Re-emits slot_changed so views, tooltips and hotbars refresh. No item
## deltas are emitted because def and count are unchanged.
func touch(i: int) -> void:
	if is_valid_index(i):
		slot_changed.emit(i)


func _emit_delta(old_def: InvItemDef, old_count: int, new_def: InvItemDef, new_count: int) -> void:
	if old_def == new_def:
		if old_def == null:
			return
		var d := new_count - old_count
		if d > 0:
			item_added.emit(new_def, d)
		elif d < 0:
			item_removed.emit(old_def, -d)
		return
	if old_def != null and old_count > 0:
		item_removed.emit(old_def, old_count)
	if new_def != null and new_count > 0:
		item_added.emit(new_def, new_count)


func clear_slot(i: int) -> void:
	set_stack(i, InvItemStack.new())


func clear_all() -> void:
	for i in _slots.size():
		if not _slots[i].is_empty():
			clear_slot(i)


# ----------------------------------------------------------------- queries

func count_of(item_id: StringName) -> int:
	var n := 0
	for s in _slots:
		if not s.is_empty() and s.def.id == item_id:
			n += s.count
	return n


func has_at_least(item_id: StringName, n: int) -> bool:
	return count_of(item_id) >= n


func first_empty() -> int:
	for i in _slots.size():
		if _slots[i].is_empty():
			return i
	return -1


func find(item_id: StringName, from_index: int = 0) -> int:
	for i in range(maxi(from_index, 0), _slots.size()):
		var s := _slots[i]
		if not s.is_empty() and s.def.id == item_id:
			return i
	return -1


func first_nonempty() -> int:
	for i in _slots.size():
		if not _slots[i].is_empty():
			return i
	return -1


func is_empty() -> bool:
	return first_nonempty() == -1


# ------------------------------------------------------------- bulk ops

## Remove `n` units of `item_id` across slots, or nothing at all.
## Validates every slot removal against the policy before touching anything.
func consume(item_id: StringName, n: int, ctx: InvTransferContext = null) -> bool:
	if n <= 0:
		return true
	var plan: Array = []  # [index, take]
	var total := 0
	for i in _slots.size():
		var s := _slots[i]
		if s.is_empty() or s.def.id != item_id:
			continue
		var want := mini(s.count, n - total)
		var rc := check_remove(i, want, ctx)
		if not rc.ok or rc.capacity <= 0:
			continue
		plan.append([i, rc.capacity])
		total += rc.capacity
		if total >= n:
			break
	if total < n:
		return false
	for p in plan:
		var i: int = p[0]
		var s := _slots[i]
		var od := s.def
		var oc := s.count
		s.split_off(p[1])  # discard the removed units
		notify_slot_mutated(i, od, oc)
	return true


## Insert as much of `stack` as fits: merge into matching stacks first, then
## empty slots. Returns the remainder (same object, count reduced; empty if
## everything fit). With all_or_nothing, either all fits or nothing changes.
## Runs filters/policy checks but NOT policy.on_commit — this is not a
## transfer. Use InvTransfer for player-driven movement.
func add_auto(stack: InvItemStack, ctx: InvTransferContext = null, all_or_nothing: bool = false) -> InvItemStack:
	if stack == null:
		return InvItemStack.new()
	if stack.is_empty():
		return stack
	var remaining := stack.count
	var probe := stack.duplicate_stack()
	var plan: Array = []  # [index, n]
	# Pass 1: merge into existing stacks.
	for i in _slots.size():
		if remaining <= 0:
			break
		if _slots[i].is_empty():
			continue
		probe.count = remaining
		var c := check_insert(i, probe, ctx)
		if c.ok and c.hint != InvDropCheck.SWAP and c.capacity > 0:
			plan.append([i, c.capacity])
			remaining -= c.capacity
	# Pass 2: empty slots.
	for i in _slots.size():
		if remaining <= 0:
			break
		if not _slots[i].is_empty():
			continue
		probe.count = remaining
		var c := check_insert(i, probe, ctx)
		if c.ok and c.capacity > 0:
			plan.append([i, c.capacity])
			remaining -= c.capacity
	if all_or_nothing and remaining > 0:
		return stack
	for p in plan:
		var i: int = p[0]
		var piece := stack.split_off(p[1])
		var cur := _slots[i]
		if cur.is_empty():
			set_stack(i, piece)
		else:
			var od := cur.def
			var oc := cur.count
			cur.absorb(piece)
			notify_slot_mutated(i, od, oc)
	return stack


## Advance component timers on every stack. Emits slot_changed for stacks
## whose components reported a change.
func tick(delta: float) -> void:
	for i in _slots.size():
		var s := _slots[i]
		if s.is_empty():
			continue
		var changed := false
		for c in s.def.components:
			if c != null and c.tick(s, delta, tick_modifier):
				changed = true
		if changed:
			slot_changed.emit(i)


# ------------------------------------------------------------ serialisation

## One dict per slot ({} for empty). Filters/policy/caps are structure, not
## state, and are NOT serialised — the game rebuilds those.
func to_array() -> Array:
	var out: Array = []
	for s in _slots:
		out.append(s.to_dict())
	return out


## Load slot contents. Resizes to match `arr` if sizes differ.
func from_array(arr: Array, db: InvItemDatabase) -> void:
	if arr.size() != _slots.size():
		resize(arr.size())
	for i in arr.size():
		var d: Variant = arr[i]
		set_stack(i, InvItemStack.from_dict(d if d is Dictionary else {}, db))


func _to_string() -> String:
	return "InvContainer(%s, %d slots)" % [id, _slots.size()]
