@tool
class_name InvTransfer
extends RefCounted

## The ONE path every item movement takes (mouse, controller, touch,
## quick-move, cursor pickup/place). Two-phase: validate everything, then
## commit, then notify policies and emit signals. On failure nothing changes.
##
## Rules, in order:
##   1. Target empty                    -> place up to amount, capped by slot max
##   2. Same item, mergeable            -> fill target, remainder stays in source
##   3. Different / unmergeable item    -> swap ONLY if the full source stack is
##                                         moving, both sides accept the incoming
##                                         stack, and neither policy has side effects
##   4. Otherwise                       -> fail, no changes


## Move `amount` units (default: whole stack) from `from[i]` to `to[j]`.
static func move(from: InvContainer, i: int, to: InvContainer, j: int, amount: int = -1, ctx: InvTransferContext = null) -> InvTransferResult:
	if from == null or to == null or not from.is_valid_index(i) or not to.is_valid_index(j):
		return InvTransferResult.failure(InvDropCheck.INVALID_INDEX, from, i, to, j)
	if from == to and i == j:
		return InvTransferResult.failure(InvDropCheck.NOOP, from, i, to, j)

	var src := from.get_stack(i)
	if src.is_empty():
		return InvTransferResult.failure(InvDropCheck.EMPTY, from, i, to, j)
	if amount < 0 or amount > src.count:
		amount = src.count
	if amount <= 0:
		return InvTransferResult.failure(InvDropCheck.NOOP, from, i, to, j)

	var rem := from.check_remove(i, amount, ctx)
	if not rem.ok:
		return InvTransferResult.failure(rem.hint, from, i, to, j)
	amount = rem.capacity

	var dst := to.get_stack(j)
	var result: InvTransferResult

	if dst.is_empty() or dst.can_merge_with(src):
		result = _place_or_merge(from, i, to, j, src, dst, amount, ctx)
	else:
		result = _swap(from, i, to, j, src, dst, amount, ctx)

	if result.ok:
		# A custom source hint (BUY from a shop) outranks the plain PLACE/MERGE
		# the target reported; a custom target hint (SELL) already won.
		if rem.hint != InvDropCheck.PLACE and (result.hint == InvDropCheck.PLACE or result.hint == InvDropCheck.MERGE):
			result.hint = rem.hint
		_after_commit(result, ctx)
	return result


## Move half (rounded up) of the source stack. Right-click pickup.
static func move_half(from: InvContainer, i: int, to: InvContainer, j: int, ctx: InvTransferContext = null) -> InvTransferResult:
	var src := from.get_stack(i) if from != null and from.is_valid_index(i) else null
	if src == null or src.is_empty():
		return InvTransferResult.failure(InvDropCheck.EMPTY, from, i, to, j)
	return move(from, i, to, j, ceili(src.count / 2.0), ctx)


## Move exactly one unit. Right-click place.
static func move_one(from: InvContainer, i: int, to: InvContainer, j: int, ctx: InvTransferContext = null) -> InvTransferResult:
	return move(from, i, to, j, 1, ctx)


## Move `amount` from from[i] into `to` wherever it fits (merge first, then
## empty slots; `merge_only` skips the empty-slot pass). Runs each partial as
## a full transfer so policies fire per slot. Returns a summary result: ok if
## anything moved.
static func move_auto(from: InvContainer, i: int, to: InvContainer, amount: int = -1, ctx: InvTransferContext = null, merge_only: bool = false) -> InvTransferResult:
	if from == null or to == null or not from.is_valid_index(i):
		return InvTransferResult.failure(InvDropCheck.INVALID_INDEX, from, i, to, -1)
	var src := from.get_stack(i)
	if src.is_empty():
		return InvTransferResult.failure(InvDropCheck.EMPTY, from, i, to, -1)
	if amount < 0 or amount > src.count:
		amount = src.count

	var summary := InvTransferResult.new()
	summary.from = from
	summary.from_index = i
	summary.to = to
	summary.to_index = -1
	summary.def = src.def
	var last_hint: StringName = InvDropCheck.FULL

	# Pass 1: merge targets. Pass 2: empty slots.
	for pass_idx in (1 if merge_only else 2):
		for j in to.size():
			if amount <= 0 or src.is_empty():
				break
			if from == to and j == i:
				continue
			var dst := to.get_stack(j)
			if pass_idx == 0 and (dst.is_empty() or not dst.can_merge_with(src)):
				continue
			if pass_idx == 1 and not dst.is_empty():
				continue
			var r := move(from, i, to, j, amount, ctx)
			if r.ok:
				summary.ok = true
				summary.hint = r.hint
				summary.moved_count += r.moved_count
				summary.to_index = j
				amount -= r.moved_count
			else:
				last_hint = r.hint
	summary.remainder = amount
	if not summary.ok:
		summary.hint = last_hint
	return summary


# ------------------------------------------------------------------ internals

static func _place_or_merge(from: InvContainer, i: int, to: InvContainer, j: int, src: InvItemStack, dst: InvItemStack, amount: int, ctx: InvTransferContext) -> InvTransferResult:
	var probe := src.duplicate_stack()
	probe.count = amount
	var ins := to.check_insert(j, probe, ctx)
	if not ins.ok:
		return InvTransferResult.failure(ins.hint, from, i, to, j)
	if ins.hint == InvDropCheck.SWAP:
		# Container says the slot is occupied by something else; we thought it
		# was mergeable. Can only happen with asymmetric component rules.
		return InvTransferResult.failure(InvDropCheck.SWAP_BLOCKED, from, i, to, j)
	var n := mini(amount, ins.capacity)
	if n <= 0:
		return InvTransferResult.failure(InvDropCheck.FULL, from, i, to, j)

	# ---- commit ----
	var moved_def := src.def
	var src_old_count := src.count
	var piece := src.split_off(n)
	from.notify_slot_mutated(i, moved_def, src_old_count)
	if dst.is_empty():
		to.set_stack(j, piece)
	else:
		var dd := dst.def
		var dc := dst.count
		dst.absorb(piece)
		to.notify_slot_mutated(j, dd, dc)

	var r := InvTransferResult.new()
	r.ok = true
	r.hint = ins.hint
	r.moved_count = n
	r.remainder = amount - n
	r.from = from
	r.from_index = i
	r.to = to
	r.to_index = j
	r.def = moved_def
	return r


static func _swap(from: InvContainer, i: int, to: InvContainer, j: int, src: InvItemStack, dst: InvItemStack, amount: int, ctx: InvTransferContext) -> InvTransferResult:
	if amount != src.count:
		return InvTransferResult.failure(InvDropCheck.SWAP_BLOCKED, from, i, to, j)
	if (from.policy != null and not from.policy.allows_swap()) \
			or (to.policy != null and not to.policy.allows_swap()):
		return InvTransferResult.failure(InvDropCheck.SWAP_BLOCKED, from, i, to, j)

	# Incoming into target slot.
	var ins := to.check_insert(j, src, ctx)
	if not ins.ok:
		return InvTransferResult.failure(ins.hint, from, i, to, j)
	if ins.capacity < src.count:
		return InvTransferResult.failure(InvDropCheck.FULL, from, i, to, j)
	# Target's current stack must be removable and must fit back in source.
	var rem := to.check_remove(j, dst.count, ctx)
	if not rem.ok:
		return InvTransferResult.failure(rem.hint, from, i, to, j)
	var back := from.check_insert(i, dst, ctx)
	if not back.ok:
		return InvTransferResult.failure(back.hint, from, i, to, j)
	if back.capacity < dst.count:
		return InvTransferResult.failure(InvDropCheck.FULL, from, i, to, j)

	# ---- commit ----  (set_stack reads the old slot content itself, so
	# order matters: from still holds src, to still holds dst.)
	from.set_stack(i, dst)
	to.set_stack(j, src)

	var r := InvTransferResult.new()
	r.ok = true
	r.hint = InvDropCheck.SWAP
	r.moved_count = src.count
	r.remainder = 0
	r.swapped = true
	r.from = from
	r.from_index = i
	r.to = to
	r.to_index = j
	r.def = src.def
	r.swapped_def = dst.def
	r.swapped_count = dst.count
	return r


static func _after_commit(r: InvTransferResult, ctx: InvTransferContext) -> void:
	if r.from.policy != null:
		r.from.policy.on_commit(r.from, &"source", r, ctx)
	if r.to != r.from and r.to.policy != null:
		r.to.policy.on_commit(r.to, &"target", r, ctx)
	r.from.transaction_committed.emit(r)
	if r.to != r.from:
		r.to.transaction_committed.emit(r)
