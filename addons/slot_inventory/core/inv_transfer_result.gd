@tool
class_name InvTransferResult
extends RefCounted

## Outcome of one InvTransfer operation. On failure nothing was changed.

var ok: bool = false
## Positive hint on success (place/merge/swap/buy/sell), failure reason otherwise.
var hint: StringName = InvDropCheck.NOOP
## Units that actually moved from source to target.
var moved_count: int = 0
## Units requested but not moved (stayed in source).
var remainder: int = 0
var swapped: bool = false

var from: InvContainer = null
var from_index: int = -1
var to: InvContainer = null
var to_index: int = -1
## The def that moved (source item). Null on failure.
var def: InvItemDef = null
## On swap: the def that came back into the source slot.
var swapped_def: InvItemDef = null
var swapped_count: int = 0


static func failure(p_hint: StringName, p_from: InvContainer, p_from_index: int, p_to: InvContainer, p_to_index: int) -> InvTransferResult:
	var r := InvTransferResult.new()
	r.ok = false
	r.hint = p_hint
	r.from = p_from
	r.from_index = p_from_index
	r.to = p_to
	r.to_index = p_to_index
	return r


func _to_string() -> String:
	if not ok:
		return "InvTransferResult(FAIL %s)" % hint
	return "InvTransferResult(%s moved=%d remainder=%d swapped=%s)" % [hint, moved_count, remainder, swapped]
