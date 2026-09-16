@tool
class_name InvShopPolicy
extends InvContainerPolicy

## Buying. The shop is an ordinary InvContainer whose slots hold the stock on
## display; taking units out of it is a purchase. Validation happens in
## can_remove (funds cap the amount, so a 5-unit request with gold for 3 buys
## 3), payment happens in on_commit, and with `infinite_stock` the slot is
## refilled to def.max_stack after every sale.
##
## Nothing can be put INTO a shop (no refunds through the shop itself — use
## an InvSellBoxPolicy container for selling). Swaps are refused because
## has_side_effects is true.
##
## Prices: def.price * price_multiplier, or override unit_price() for
## per-item logic (discounts, reputation, day-of-week specials).

## Refill each slot to def.max_stack after a sale.
@export var infinite_stock: bool = true
@export var price_multiplier: float = 1.0
## Format for slot_caption(); %d is the unit price. Empty = no caption.
@export var caption_format: String = "%dg"


func _init() -> void:
	has_side_effects = true


func unit_price(def: InvItemDef, _ctx: InvTransferContext) -> int:
	if def == null:
		return 0
	return maxi(int(round(def.price * price_multiplier)), 0)


func can_insert(_container: InvContainer, _index: int, _stack: InvItemStack, _ctx: InvTransferContext) -> InvDropCheck:
	return InvDropCheck.reject(InvDropCheck.WRONG_TYPE)


func can_remove(container: InvContainer, index: int, amount: int, ctx: InvTransferContext) -> InvDropCheck:
	var s := container.get_stack(index)
	var price := unit_price(s.def, ctx)
	if price <= 0:
		return InvDropCheck.accept(InvDropCheck.BUY, amount)
	var wallet: Object = ctx.wallet if ctx != null else null
	var affordable := int(InvWallet.gold_of(wallet) / float(price))
	var n := mini(amount, affordable)
	if n <= 0:
		return InvDropCheck.reject(InvDropCheck.NO_FUNDS)
	return InvDropCheck.accept(InvDropCheck.BUY, n)


func on_commit(container: InvContainer, role: StringName, result: InvTransferResult, ctx: InvTransferContext) -> void:
	if role != &"source":
		return
	var price := unit_price(result.def, ctx)
	var cost := price * result.moved_count
	if cost > 0:
		var wallet: Object = ctx.wallet if ctx != null else null
		if not InvWallet.spend_from(wallet, cost):
			# can_remove validated this a moment ago; only a racing wallet
			# change can get here. Nothing to roll back safely — report it.
			push_warning("InvShopPolicy: wallet refused %d after validation" % cost)
	if infinite_stock and result.def != null:
		container.set_stack(result.from_index, InvItemStack.make(result.def, result.def.max_stack))


func bulk_pickup_enabled() -> bool:
	return true


func slot_tooltip_lines(container: InvContainer, index: int, ctx: InvTransferContext) -> Array:
	var s := container.get_stack(index)
	if s.is_empty():
		return []
	var price := unit_price(s.def, ctx)
	if price <= 0:
		return [{"text": "Free", "style": InvTooltipField.STYLE_POSITIVE}]
	var wallet: Object = ctx.wallet if ctx != null else null
	var style := InvTooltipField.STYLE_ACCENT if InvWallet.gold_of(wallet) >= price else InvTooltipField.STYLE_NEGATIVE
	return [{"text": "Buy: %dg" % price, "style": style}]


func slot_caption(container: InvContainer, index: int, ctx: InvTransferContext) -> String:
	if caption_format == "":
		return ""
	var s := container.get_stack(index)
	if s.is_empty():
		return ""
	return caption_format % unit_price(s.def, ctx)
