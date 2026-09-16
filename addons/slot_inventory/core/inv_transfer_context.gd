@tool
class_name InvTransferContext
extends RefCounted

## Runtime dependencies handed to every rules hook. The inventory core owns
## none of these; the game injects them. All fields are optional — hooks
## must tolerate null.

## Anything exposing get_gold() -> int, try_spend(int) -> bool, add_gold(int).
## Duck-typed so the game keeps ownership of currency. (Phase 5)
var wallet: Object = null

## Ordered list of currently open containers + routing rules. (Phase 2)
var open_context: RefCounted = null

## Free-form extra data for game-specific policies (day index, NPC id...).
var meta: Dictionary = {}


static func make(p_wallet: Object = null, p_open_context: RefCounted = null, p_meta: Dictionary = {}) -> InvTransferContext:
	var c := InvTransferContext.new()
	c.wallet = p_wallet
	c.open_context = p_open_context
	c.meta = p_meta
	return c
