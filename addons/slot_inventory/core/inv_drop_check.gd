@tool
class_name InvDropCheck
extends RefCounted

## Result of asking "can this go here / come out of here?".
## `hint` drives ALL cursor and slot feedback downstream — the UI never
## re-derives rules. `capacity` is how many units the check would allow.

# Positive hints
const PLACE := &"place"
const MERGE := &"merge"
const SWAP := &"swap"
const BUY := &"buy"
const SELL := &"sell"

# Negative hints
const FULL := &"full"
const WRONG_TYPE := &"wrong_type"
const LOCKED := &"locked"
const EMPTY := &"empty"
const INVALID_INDEX := &"invalid_index"
const NOOP := &"noop"
const NO_FUNDS := &"no_funds"
const SWAP_BLOCKED := &"swap_blocked"

var ok: bool = false
var hint: StringName = PLACE
var capacity: int = 0


static func accept(p_hint: StringName = PLACE, p_capacity: int = 0) -> InvDropCheck:
	var c := InvDropCheck.new()
	c.ok = true
	c.hint = p_hint
	c.capacity = p_capacity
	return c


static func reject(p_hint: StringName) -> InvDropCheck:
	var c := InvDropCheck.new()
	c.ok = false
	c.hint = p_hint
	c.capacity = 0
	return c


func _to_string() -> String:
	return "InvDropCheck(ok=%s, hint=%s, capacity=%d)" % [ok, hint, capacity]
