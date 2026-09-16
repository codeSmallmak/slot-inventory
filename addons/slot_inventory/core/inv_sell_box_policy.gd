@tool
class_name InvSellBoxPolicy
extends InvContainerPolicy

## Selling. Put items in, get paid. Three flavours from one policy:
##
##   Merchant counter   payment = IMMEDIATE, buyback = true, consume = false
##     Paid on drop; the item sits in the box and can be bought back at the
##     same price while the box is open. Clear the box when the shop closes.
##   Merchant (no returns)  payment = IMMEDIATE, consume = true
##     Paid on drop; the item vanishes.
##   Shipping bin        payment = DEFERRED, buyback = true
##     Nothing paid until settle() is called (end of day). Items can be
##     taken back before then.
##
## What sells: def.sell_price > 0, or any item when `accept_unsellable` is
## on (worth 0). Prices: def.sell_price * price_multiplier, or override
## unit_sell_price().

enum Payment { IMMEDIATE, DEFERRED }

@export var payment: Payment = Payment.IMMEDIATE
## Allow taking items back out. On IMMEDIATE payment the refund is charged
## (and refused with NO_FUNDS if the player already spent the gold).
@export var buyback: bool = true
## IMMEDIATE only: destroy the item on sale instead of keeping it in the box.
@export var consume: bool = false
@export var accept_unsellable: bool = false
@export var price_multiplier: float = 1.0
## Format for slot_caption(); %d is the unit sell price. Empty = none.
@export var caption_format: String = "+%dg"


func _init() -> void:
	has_side_effects = true


func unit_sell_price(def: InvItemDef, _ctx: InvTransferContext) -> int:
	if def == null:
		return 0
	return maxi(int(round(def.sell_price * price_multiplier)), 0)


func can_insert(_container: InvContainer, _index: int, stack: InvItemStack, ctx: InvTransferContext) -> InvDropCheck:
	if unit_sell_price(stack.def, ctx) <= 0 and not accept_unsellable:
		return InvDropCheck.reject(InvDropCheck.WRONG_TYPE)
	return InvDropCheck.accept(InvDropCheck.SELL)


func can_remove(container: InvContainer, index: int, amount: int, ctx: InvTransferContext) -> InvDropCheck:
	if not buyback:
		return InvDropCheck.reject(InvDropCheck.LOCKED)
	if payment == Payment.DEFERRED:
		return InvDropCheck.accept(InvDropCheck.PLACE, amount)
	var s := container.get_stack(index)
	var price := unit_sell_price(s.def, ctx)
	if price <= 0:
		return InvDropCheck.accept(InvDropCheck.BUY, amount)
	var wallet: Object = ctx.wallet if ctx != null else null
	var affordable := int(InvWallet.gold_of(wallet) / float(price))
	var n := mini(amount, affordable)
	if n <= 0:
		return InvDropCheck.reject(InvDropCheck.NO_FUNDS)
	return InvDropCheck.accept(InvDropCheck.BUY, n)


func on_commit(container: InvContainer, role: StringName, result: InvTransferResult, ctx: InvTransferContext) -> void:
	if payment != Payment.IMMEDIATE:
		return
	var wallet: Object = ctx.wallet if ctx != null else null
	var price := unit_sell_price(result.def, ctx)
	if role == &"target":
		InvWallet.add_to(wallet, price * result.moved_count)
		if consume:
			container.clear_slot(result.to_index)
	elif role == &"source":
		if not InvWallet.spend_from(wallet, price * result.moved_count):
			push_warning("InvSellBoxPolicy: buyback refund refused after validation")


## DEFERRED: pay out everything in `container`, clear it, return the total.
## Safe to call on an IMMEDIATE box too (it just clears and returns 0).
func settle(container: InvContainer, wallet: Object, ctx: InvTransferContext = null) -> int:
	var total := 0
	if payment == Payment.DEFERRED:
		for i in container.size():
			var s := container.get_stack(i)
			if not s.is_empty():
				total += unit_sell_price(s.def, ctx) * s.count
	container.clear_all()
	InvWallet.add_to(wallet, total)
	return total


## Value of everything currently in the box at today's prices.
func pending_value(container: InvContainer, ctx: InvTransferContext = null) -> int:
	var total := 0
	for i in container.size():
		var s := container.get_stack(i)
		if not s.is_empty():
			total += unit_sell_price(s.def, ctx) * s.count
	return total


func slot_tooltip_lines(container: InvContainer, index: int, ctx: InvTransferContext) -> Array:
	var s := container.get_stack(index)
	if s.is_empty():
		return []
	var price := unit_sell_price(s.def, ctx)
	var out: Array = []
	if payment == Payment.DEFERRED:
		out.append({"text": "Ships for %dg (x%d = %dg)" % [price, s.count, price * s.count], "style": InvTooltipField.STYLE_ACCENT})
	else:
		out.append({"text": "Sold for %dg each" % price, "style": InvTooltipField.STYLE_ACCENT})
	if buyback:
		out.append({"text": "Take back: %s" % ("free" if payment == Payment.DEFERRED else "%dg each" % price), "style": InvTooltipField.STYLE_MUTED})
	else:
		out.append({"text": "No returns", "style": InvTooltipField.STYLE_NEGATIVE})
	return out


func slot_caption(container: InvContainer, index: int, ctx: InvTransferContext) -> String:
	if caption_format == "":
		return ""
	var s := container.get_stack(index)
	if s.is_empty():
		return ""
	return caption_format % unit_sell_price(s.def, ctx)
