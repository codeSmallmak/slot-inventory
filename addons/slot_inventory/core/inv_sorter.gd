@tool
class_name InvSorter
extends RefCounted

## Sort / auto-stack for one container. Both operations are all-or-nothing:
## every slot is validated (policy can_remove, filters on re-insert) before
## anything changes, and if re-placement fails midway the original contents
## are restored. Neither runs policy.on_commit — these are reorganisations,
## not transfers.
##
## Default order: by first tag (alphabetical, untagged last), then id, then
## count descending. Pass your own `less(a: InvItemStack, b: InvItemStack)`.


## Merge like stacks together and pack them toward the front, keeping the
## original relative order. Returns false (no change) if any slot is locked.
static func compact(c: InvContainer, ctx: InvTransferContext = null) -> bool:
	return _run(c, ctx, Callable(), true)


## Merge like stacks and sort them. Returns false (no change) if any slot is
## locked or nothing could be re-placed.
static func sort(c: InvContainer, ctx: InvTransferContext = null, less: Callable = Callable()) -> bool:
	return _run(c, ctx, less, false)


static func default_less(a: InvItemStack, b: InvItemStack) -> bool:
	var ta := String(a.def.tags[0]) if not a.def.tags.is_empty() else "~"
	var tb := String(b.def.tags[0]) if not b.def.tags.is_empty() else "~"
	if ta != tb:
		return ta < tb
	if a.def.id != b.def.id:
		return String(a.def.id) < String(b.def.id)
	return a.count > b.count


# ---------------------------------------------------------------- internals

static func _run(c: InvContainer, ctx: InvTransferContext, less: Callable, keep_order: bool) -> bool:
	if c == null or c.size() == 0:
		return false

	# 1. Validate removal of everything and snapshot.
	var original: Array[InvItemStack] = []
	var working: Array[InvItemStack] = []
	for i in c.size():
		var s := c.get_stack(i)
		original.append(s)
		if s.is_empty():
			continue
		var rc := c.check_remove(i, s.count, ctx)
		if not rc.ok or rc.capacity < s.count:
			return false
		working.append(s.duplicate_stack())

	if working.is_empty():
		return false

	# 2. Merge like stacks (respecting def.max_stack and component rules).
	var merged: Array[InvItemStack] = []
	for s in working:
		for m in merged:
			if s.is_empty():
				break
			if m.can_merge_with(s) and m.count < m.max_stack():
				var take := mini(m.max_stack() - m.count, s.count)
				m.absorb(s.split_off(take))
		if not s.is_empty():
			merged.append(s)

	# 3. Order.
	if not keep_order:
		var cmp: Callable = less if less.is_valid() else InvSorter.default_less
		merged.sort_custom(cmp)

	# 4. Clear, then place each stack in the first empty slot that accepts it,
	#    splitting when a slot cap is lower than the stack.
	for i in c.size():
		if not original[i].is_empty():
			c.set_stack(i, InvItemStack.new())
	var ok := true
	for s in merged:
		while not s.is_empty():
			var placed := false
			for i in c.size():
				if not c.is_slot_empty(i):
					continue
				var chk := c.check_insert(i, s, ctx)
				if not chk.ok or chk.capacity <= 0:
					continue
				c.set_stack(i, s.split_off(chk.capacity))
				placed = true
				break
			if not placed:
				ok = false
				break
		if not ok:
			break

	if not ok:
		# 5. Restore snapshot exactly.
		for i in c.size():
			c.set_stack(i, original[i])
		return false
	return true
