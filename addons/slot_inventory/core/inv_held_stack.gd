@tool
class_name InvHeldStack
extends RefCounted

## The stack on the cursor. Internally a 1-slot InvContainer (id &"held") so
## pickup and place are ordinary InvTransfer moves: every policy, filter and
## cap applies exactly as it does slot-to-slot, and a failed placement
## leaves the item held (nothing changes on failure).
##
## Remembers where the stack came from so the UI can return it when a
## screen closes (return_home). Never talks to the scene tree.

signal changed()

var _hand: InvContainer = InvContainer.new(1, &"held")

var origin_container: InvContainer = null
var origin_index: int = -1


func _init() -> void:
	_hand.slot_changed.connect(_on_hand_slot_changed)


# ------------------------------------------------------------------ queries

## The 1-slot container backing the hand. Exposed so game code can pass it to
## InvTransfer directly (e.g. drag-drop onto a world target).
func container() -> InvContainer:
	return _hand


## Live stack reference. Treat as read-only.
func stack() -> InvItemStack:
	return _hand.get_stack(0)


func is_holding() -> bool:
	return not _hand.is_slot_empty(0)


func def() -> InvItemDef:
	return stack().def


func count() -> int:
	return stack().count


# ------------------------------------------------------------------- pickup

## Pick up `amount` (default all) from `from[i]`.
## Empty hand      -> place into hand, remember origin.
## Same item held  -> merge into hand up to def.max_stack; rest stays in slot.
## Other item held -> swap (whole slot stack for whole held stack), if both
##                    sides accept. Origin is kept from the first pickup.
func pickup(from: InvContainer, i: int, amount: int = -1, ctx: InvTransferContext = null) -> InvTransferResult:
	var was_empty := not is_holding()
	var r := InvTransfer.move(from, i, _hand, 0, amount, ctx)
	if r.ok and was_empty:
		origin_container = from
		origin_index = i
	return r


## Pick up half (rounded up). Right-click pickup.
func pickup_half(from: InvContainer, i: int, ctx: InvTransferContext = null) -> InvTransferResult:
	var was_empty := not is_holding()
	var r := InvTransfer.move_half(from, i, _hand, 0, ctx)
	if r.ok and was_empty:
		origin_container = from
		origin_index = i
	return r


# -------------------------------------------------------------------- place

## Place `amount` (default all) of the held stack into `to[j]`.
## Empty / mergeable target -> place or merge, remainder stays held.
## Other item in target     -> swap: hand now holds the target's stack.
## Any failure              -> nothing changes, item stays held.
func place(to: InvContainer, j: int, amount: int = -1, ctx: InvTransferContext = null) -> InvTransferResult:
	if not is_holding():
		return InvTransferResult.failure(InvDropCheck.EMPTY, _hand, 0, to, j)
	var r := InvTransfer.move(_hand, 0, to, j, amount, ctx)
	if r.ok and not is_holding():
		_clear_origin()
	return r


## Place exactly one unit. Right-click place.
func place_one(to: InvContainer, j: int, ctx: InvTransferContext = null) -> InvTransferResult:
	return place(to, j, 1, ctx)


## Place as much as fits anywhere in `to` (merge first, then empty slots).
func place_auto(to: InvContainer, amount: int = -1, ctx: InvTransferContext = null) -> InvTransferResult:
	if not is_holding():
		return InvTransferResult.failure(InvDropCheck.EMPTY, _hand, 0, to, -1)
	var r := InvTransfer.move_auto(_hand, 0, to, amount, ctx)
	if not is_holding():
		_clear_origin()
	return r


## Feedback for the UI while hovering `to[j]` with the held stack: what would
## happen (PLACE / MERGE / SWAP / a rejection hint). Does not mutate.
func preview(to: InvContainer, j: int, ctx: InvTransferContext = null) -> InvDropCheck:
	if not is_holding():
		return InvDropCheck.reject(InvDropCheck.EMPTY)
	if to == null or not to.is_valid_index(j):
		return InvDropCheck.reject(InvDropCheck.INVALID_INDEX)
	return to.check_insert(j, stack(), ctx)


# ------------------------------------------------------------------ collect

## Double-click gather: pull every stack mergeable with the held one out of
## `sources` (in order, slot order) until the hand is full. Runs one transfer
## per source slot so policies fire per slot. Returns units gathered.
func collect(sources: Array, ctx: InvTransferContext = null) -> int:
	if not is_holding():
		return 0
	var gathered := 0
	var held := stack()
	for c in sources:
		var src := c as InvContainer
		if src == null or src == _hand:
			continue
		for i in src.size():
			if held.count >= held.max_stack():
				return gathered
			var s := src.get_stack(i)
			if s.is_empty() or not held.can_merge_with(s):
				continue
			var r := InvTransfer.move(src, i, _hand, 0, -1, ctx)
			if r.ok:
				gathered += r.moved_count
	return gathered


# ------------------------------------------------------------- return / drop

## Put the held stack back where it came from: origin slot first, then
## anywhere in the origin container. Returns the units that could NOT be
## returned (0 = hand is now empty). The caller decides what to do with the
## rest (usually drop_to_world / return to fallback container).
func return_home(ctx: InvTransferContext = null) -> int:
	if not is_holding():
		return 0
	if origin_container != null:
		if origin_container.is_valid_index(origin_index):
			# Only place/merge into the origin slot — never swap something
			# else out of it just to put this back.
			var dst := origin_container.get_stack(origin_index)
			if dst.is_empty() or dst.can_merge_with(stack()):
				InvTransfer.move(_hand, 0, origin_container, origin_index, -1, ctx)
		if is_holding():
			InvTransfer.move_auto(_hand, 0, origin_container, -1, ctx)
	if not is_holding():
		_clear_origin()
	return count()


## Try `return_home`, then each container in `fallbacks` in order.
## Returns units still held afterwards.
func return_home_or(fallbacks: Array, ctx: InvTransferContext = null) -> int:
	return_home(ctx)
	for c in fallbacks:
		if not is_holding():
			break
		var dst := c as InvContainer
		if dst != null:
			InvTransfer.move_auto(_hand, 0, dst, -1, ctx)
	if not is_holding():
		_clear_origin()
	return count()


## Remove the held stack from the hand and hand it to the caller (world drop,
## destroy). Bypasses transfer rules on purpose — the item is leaving the
## inventory system. Emits item_removed on the hand container.
func take() -> InvItemStack:
	var out := stack().duplicate_stack()
	_hand.clear_slot(0)
	_clear_origin()
	return out


# ---------------------------------------------------------------- internals

func _clear_origin() -> void:
	origin_container = null
	origin_index = -1


func _on_hand_slot_changed(_i: int) -> void:
	changed.emit()


func _to_string() -> String:
	return "InvHeldStack(%s)" % stack()
