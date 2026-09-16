@tool
extends McpTestSuite

## Phase 5 headless tests: InvWallet, InvShopPolicy (buying, bulk, hold-
## repeat through the session), InvSellBoxPolicy (counter, no-returns,
## shipping bin), and how they flow through InvTransfer / InvHeldStack.


var db: InvItemDatabase
var seed: InvItemDef     # price 10, sell 3, max 99
var wood: InvItemDef     # price 0 (not for sale), sell 2, max 50
var hoe: InvItemDef      # price 120, sell 40, max 1
var junk: InvItemDef     # no prices at all


func suite_name() -> String:
	return "inv_shop"


func suite_setup(_ctx: Dictionary) -> void:
	db = InvItemDatabase.new()
	seed = _def(&"seed", 99, 10, 3)
	wood = _def(&"wood", 50, 0, 2)
	hoe = _def(&"hoe", 1, 120, 40)
	junk = _def(&"junk", 10, 0, 0)


func _def(id: StringName, max_stack: int, price: int, sell: int) -> InvItemDef:
	var d := InvItemDef.new()
	d.id = id
	d.max_stack = max_stack
	d.price = price
	d.sell_price = sell
	db.register(d)
	return d


func _c(n: int, id: StringName = &"c") -> InvContainer:
	return InvContainer.new(n, id)


func _put(c: InvContainer, i: int, def: InvItemDef, n: int) -> void:
	c.set_stack(i, InvItemStack.make(def, n))


func _shop(defs: Array, infinite: bool = true) -> InvContainer:
	var c := _c(defs.size(), &"shop")
	var p := InvShopPolicy.new()
	p.infinite_stock = infinite
	c.policy = p
	for i in defs.size():
		var d: InvItemDef = defs[i]
		_put(c, i, d, d.max_stack)
	return c


func _ctx(gold: int) -> InvTransferContext:
	return InvTransferContext.make(InvWallet.new(gold))


# ------------------------------------------------------------------- wallet

func test_wallet_basics() -> void:
	var w := InvWallet.new(50)
	var events := []
	w.changed.connect(func(g: int) -> void: events.append(g))
	assert_true(w.try_spend(20))
	assert_false(w.try_spend(31))
	assert_true(w.try_spend(0))
	w.add_gold(5)
	w.add_gold(0)
	assert_eq(w.get_gold(), 35)
	assert_eq(events, [30, 35])
	assert_eq(InvWallet.gold_of(null), 0)
	assert_false(InvWallet.spend_from(null, 5))
	assert_true(InvWallet.spend_from(null, 0))


# ---------------------------------------------------------------- shop: core

func test_shop_check_remove_caps_by_funds() -> void:
	var shop := _shop([seed])
	var ctx := _ctx(35)  # 3 seeds
	var c := shop.check_remove(0, 10, ctx)
	assert_true(c.ok)
	assert_eq(c.hint, InvDropCheck.BUY)
	assert_eq(c.capacity, 3)
	assert_eq(shop.check_remove(0, 10, _ctx(9)).hint, InvDropCheck.NO_FUNDS)
	assert_eq(shop.check_remove(0, 10, null).hint, InvDropCheck.NO_FUNDS, "no wallet, no purchase")


func test_shop_free_item_is_unlimited() -> void:
	var shop := _shop([wood])
	var c := shop.check_remove(0, 50, _ctx(0))
	assert_true(c.ok)
	assert_eq(c.capacity, 50)


func test_buy_via_transfer_charges_and_restocks() -> void:
	var shop := _shop([seed])
	var inv := _c(2)
	var ctx := _ctx(100)
	var r := InvTransfer.move(shop, 0, inv, 0, 5, ctx)
	assert_true(r.ok)
	assert_eq(r.hint, InvDropCheck.BUY)
	assert_eq(r.moved_count, 5)
	assert_eq(ctx.wallet.get_gold(), 50)
	assert_eq(inv.get_stack(0).count, 5)
	assert_eq(shop.get_stack(0).count, 99, "infinite stock refilled")


func test_buy_partial_when_short_on_gold() -> void:
	var shop := _shop([seed])
	var inv := _c(1)
	var ctx := _ctx(25)
	var r := InvTransfer.move(shop, 0, inv, 0, 10, ctx)
	assert_true(r.ok)
	assert_eq(r.moved_count, 2)
	assert_eq(ctx.wallet.get_gold(), 5)
	var r2 := InvTransfer.move(shop, 0, inv, 0, 1, ctx)
	assert_false(r2.ok)
	assert_eq(r2.hint, InvDropCheck.NO_FUNDS)


func test_finite_shop_depletes() -> void:
	var shop := _shop([hoe], false)
	var inv := _c(2)
	var ctx := _ctx(500)
	assert_true(InvTransfer.move(shop, 0, inv, 0, 1, ctx).ok)
	assert_true(shop.is_slot_empty(0))
	assert_eq(ctx.wallet.get_gold(), 380)
	assert_eq(InvTransfer.move(shop, 0, inv, 1, 1, ctx).hint, InvDropCheck.EMPTY)


func test_nothing_goes_into_a_shop() -> void:
	var shop := _shop([seed])
	shop.resize(2)  # slot 1 empty
	var inv := _c(1)
	_put(inv, 0, wood, 5)
	var ctx := _ctx(100)
	assert_eq(InvTransfer.move(inv, 0, shop, 1, -1, ctx).hint, InvDropCheck.WRONG_TYPE)
	assert_eq(inv.get_stack(0).count, 5)
	# Swap with a shop slot is refused (side effects).
	_put(inv, 0, hoe, 1)
	assert_eq(InvTransfer.move(inv, 0, shop, 0, -1, ctx).hint, InvDropCheck.SWAP_BLOCKED)


func test_shop_quick_move_buys_into_inventory() -> void:
	var shop := _shop([seed])
	var inv := _c(1)
	var ctx := _ctx(45)
	var oc := InvOpenContext.new()
	ctx.open_context = oc
	oc.open(inv)
	oc.open(shop, &"external")
	var r := oc.quick_move(shop, 0, 5, ctx)
	assert_true(r.ok)
	assert_eq(r.moved_count, 4, "capped by gold")
	assert_eq(ctx.wallet.get_gold(), 5)


func test_shop_price_multiplier_and_caption() -> void:
	var shop := _shop([seed])
	var p := shop.policy as InvShopPolicy
	p.price_multiplier = 1.5
	var ctx := _ctx(100)
	assert_eq(p.unit_price(seed, ctx), 15)
	assert_eq(p.slot_caption(shop, 0, ctx), "15g")
	p.caption_format = ""
	assert_eq(p.slot_caption(shop, 0, ctx), "")


func test_shop_commit_signal_and_policy_fires_once_per_sale() -> void:
	var shop := _shop([seed])
	var inv := _c(1)
	var ctx := _ctx(100)
	var commits := []
	shop.transaction_committed.connect(func(r: InvTransferResult) -> void: commits.append(r.moved_count))
	InvTransfer.move(shop, 0, inv, 0, 3, ctx)
	InvTransfer.move(shop, 0, inv, 0, 2, ctx)
	assert_eq(commits, [3, 2])
	assert_eq(ctx.wallet.get_gold(), 50)


# --------------------------------------------------------------- shop: UI

func _session(gold: int) -> InvUISession:
	var s := InvUISession.new()
	s.shake_on_reject = false
	s.set_wallet(InvWallet.new(gold))
	track(s)
	return s


func _view(c: InvContainer, group: StringName, origin: Vector2 = Vector2.ZERO) -> InvContainerView:
	var v := InvContainerView.new()
	v.group = group
	v.bind(c)
	for i in v.slot_count():
		var sv := v.get_view(i)
		sv.animate_changes = false
		sv.size = Vector2(48, 48)
		sv.position = origin + Vector2(i * 50, 0)
	track(v)
	return v


func _mb(button: int, pressed: bool, pos: Vector2, shift: bool = false, ctrl: bool = false, dbl: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.global_position = pos
	e.position = pos
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	e.double_click = dbl
	return e


func _click(view: InvSlotView, button: int = MOUSE_BUTTON_LEFT, shift: bool = false, ctrl: bool = false, dbl: bool = false) -> void:
	var pos := view.get_global_rect().get_center()
	view._gui_input(_mb(button, true, pos, shift, ctrl, dbl))
	view._gui_input(_mb(button, false, pos, shift, ctrl, dbl))


func test_session_lmb_buys_one_into_hand_rmb_too() -> void:
	var s := _session(100)
	var shop := _shop([seed])
	var sv := _view(shop, &"external")
	s.register(sv)
	assert_true(InvUISession.is_vendor(sv.get_view(0)))
	_click(sv.get_view(0))
	assert_eq(s.held.count(), 1)
	_click(sv.get_view(0), MOUSE_BUTTON_RIGHT)
	assert_eq(s.held.count(), 2, "RMB is also 'take one' on a vendor")
	assert_eq(s.ctx.wallet.get_gold(), 80)
	assert_eq(shop.get_stack(0).count, 99)


func test_session_bulk_modifiers() -> void:
	var s := _session(1000)
	var shop := _shop([seed])
	var sv := _view(shop, &"external")
	s.register(sv)
	_click(sv.get_view(0), MOUSE_BUTTON_LEFT, true)
	assert_eq(s.held.count(), 5)
	_click(sv.get_view(0), MOUSE_BUTTON_LEFT, false, true)
	assert_eq(s.held.count(), 15)
	_click(sv.get_view(0), MOUSE_BUTTON_LEFT, true, true)
	assert_eq(s.held.count(), 40)
	assert_eq(s.ctx.wallet.get_gold(), 600)


func test_session_bulk_is_capped_by_gold_and_hand() -> void:
	var s := _session(70)
	var shop := _shop([seed])
	var sv := _view(shop, &"external")
	s.register(sv)
	var rejected := []
	s.transfer_rejected.connect(func(r: InvTransferResult) -> void: rejected.append(r.hint))
	_click(sv.get_view(0), MOUSE_BUTTON_LEFT, false, true)  # wants 10, affords 7
	assert_eq(s.held.count(), 7)
	assert_eq(s.ctx.wallet.get_gold(), 0)
	_click(sv.get_view(0))
	assert_eq(rejected, [InvDropCheck.NO_FUNDS])
	# Hand cap: a 1-max item can't stack in the hand.
	var s2 := _session(1000)
	var shop2 := _shop([hoe])
	var sv2 := _view(shop2, &"external")
	s2.register(sv2)
	_click(sv2.get_view(0))
	var r := s2.take(sv2.get_view(0), 1)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.FULL)
	assert_eq(s2.ctx.wallet.get_gold(), 880, "only one hoe charged")


func test_session_vendor_ignores_collect_and_quick_move_gestures() -> void:
	var s := _session(1000)
	var shop := _shop([seed])
	var inv := _c(2)
	var sv := _view(shop, &"external")
	var iv := _view(inv, &"player", Vector2(0, 100))
	s.register(sv)
	s.register(iv)
	var v := sv.get_view(0)
	var pos := v.get_global_rect().get_center()
	v._gui_input(_mb(MOUSE_BUTTON_LEFT, true, pos))
	v._gui_input(_mb(MOUSE_BUTTON_LEFT, false, pos))
	v._gui_input(_mb(MOUSE_BUTTON_LEFT, true, pos, false, false, true))  # double-click
	v._gui_input(_mb(MOUSE_BUTTON_LEFT, false, pos, false, false, true))
	assert_eq(s.held.count(), 2, "double-click = two single purchases, not a collect")
	assert_true(inv.is_empty(), "shift never quick-moved anything")


func test_session_holding_other_item_cannot_buy_or_sell_to_shop() -> void:
	var s := _session(1000)
	var shop := _shop([seed])
	var inv := _c(1)
	_put(inv, 0, wood, 5)
	var sv := _view(shop, &"external")
	var iv := _view(inv, &"player", Vector2(0, 100))
	s.register(sv)
	s.register(iv)
	_click(iv.get_view(0))
	assert_eq(s.held.def(), wood)
	var r := s.take(sv.get_view(0), 1)
	assert_false(r.ok)
	assert_eq(r.hint, InvDropCheck.SWAP_BLOCKED)
	assert_eq(s.held.def(), wood)
	assert_eq(s.held.count(), 5)
	assert_eq(s.ctx.wallet.get_gold(), 1000)


func test_session_hold_repeat_accelerates_and_stops_when_broke() -> void:
	var s := _session(100)  # 10 seeds
	s.hold_repeat_delay = 0.5
	s.hold_repeat_interval = 0.2
	s.hold_repeat_min = 0.05
	s.hold_repeat_accel = 0.5
	var shop := _shop([seed])
	var sv := _view(shop, &"external")
	s.register(sv)
	var v := sv.get_view(0)
	v._gui_input(_mb(MOUSE_BUTTON_LEFT, true, v.get_global_rect().get_center()))
	assert_eq(s.held.count(), 1)
	assert_true(s.is_hold_repeating())
	s.tick_hold(0.4)
	assert_eq(s.held.count(), 1, "still inside the initial delay")
	s.tick_hold(0.1)
	assert_eq(s.held.count(), 2, "first repeat at the delay")
	s.tick_hold(0.1)
	assert_eq(s.held.count(), 3, "interval halves: 0.1")
	s.tick_hold(0.05)
	assert_eq(s.held.count(), 4, "then clamps at min 0.05")
	s.tick_hold(5.0)
	assert_eq(s.held.count(), 10, "burst until gold runs out")
	assert_false(s.is_hold_repeating(), "stopped on NO_FUNDS")
	assert_eq(s.ctx.wallet.get_gold(), 0)


func test_session_release_stops_hold() -> void:
	var s := _session(1000)
	var shop := _shop([seed])
	var sv := _view(shop, &"external")
	s.register(sv)
	var v := sv.get_view(0)
	var pos := v.get_global_rect().get_center()
	v._gui_input(_mb(MOUSE_BUTTON_LEFT, true, pos))
	assert_true(s.is_hold_repeating())
	v._gui_input(_mb(MOUSE_BUTTON_LEFT, false, pos))
	assert_false(s.is_hold_repeating())
	s.tick_hold(10.0)
	assert_eq(s.held.count(), 1)
	# Bulk clicks never start a repeat.
	v._gui_input(_mb(MOUSE_BUTTON_LEFT, true, pos, true))
	assert_false(s.is_hold_repeating())


func test_session_hover_feedback_on_shop_reports_buy_or_no_funds() -> void:
	var s := _session(5)
	var shop := _shop([seed])
	var inv := _c(1)
	_put(inv, 0, seed, 3)
	var sv := _view(shop, &"external")
	var iv := _view(inv, &"player", Vector2(0, 100))
	s.register(sv)
	s.register(iv)
	assert_eq(sv.get_view(0).ctx, s.ctx, "slot views get the session ctx for captions")
	_click(iv.get_view(0))  # hold 3 seeds
	var shop_slot := sv.get_view(0)
	shop_slot._notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_true(shop_slot.feedback != null)
	assert_false(shop_slot.feedback.ok, "can't put things into the shop")
	assert_false(shop_slot.accepts_held)


# ---------------------------------------------------------------- sell box

func _box(payment: InvSellBoxPolicy.Payment, buyback: bool = true, consume: bool = false, n: int = 2) -> InvContainer:
	var c := _c(n, &"box")
	var p := InvSellBoxPolicy.new()
	p.payment = payment
	p.buyback = buyback
	p.consume = consume
	c.policy = p
	return c


func test_counter_pays_on_drop_and_refunds_on_buyback() -> void:
	var box := _box(InvSellBoxPolicy.Payment.IMMEDIATE)
	var inv := _c(1)
	_put(inv, 0, wood, 10)
	var ctx := _ctx(0)
	var r := InvTransfer.move(inv, 0, box, 0, -1, ctx)
	assert_true(r.ok)
	assert_eq(r.hint, InvDropCheck.SELL)
	assert_eq(ctx.wallet.get_gold(), 20)
	assert_eq(box.get_stack(0).count, 10, "item waits in the box")
	# Buy 4 back.
	var back := InvTransfer.move(box, 0, inv, 0, 4, ctx)
	assert_true(back.ok)
	assert_eq(back.hint, InvDropCheck.BUY)
	assert_eq(ctx.wallet.get_gold(), 12)
	assert_eq(inv.get_stack(0).count, 4)
	assert_eq(box.get_stack(0).count, 6)


func test_counter_buyback_limited_by_gold() -> void:
	var box := _box(InvSellBoxPolicy.Payment.IMMEDIATE)
	var inv := _c(1)
	_put(inv, 0, wood, 10)
	var ctx := _ctx(0)
	InvTransfer.move(inv, 0, box, 0, -1, ctx)   # +20
	ctx.wallet.try_spend(15)                     # spent most of it: 5 left
	var back := InvTransfer.move(box, 0, inv, 0, 10, ctx)
	assert_true(back.ok)
	assert_eq(back.moved_count, 2, "2 units at 2g each")
	assert_eq(ctx.wallet.get_gold(), 1)
	assert_eq(InvTransfer.move(box, 0, inv, 0, 1, ctx).hint, InvDropCheck.NO_FUNDS)


func test_counter_no_returns_consumes() -> void:
	var box := _box(InvSellBoxPolicy.Payment.IMMEDIATE, false, true)
	var inv := _c(1)
	_put(inv, 0, hoe, 1)
	var ctx := _ctx(0)
	assert_true(InvTransfer.move(inv, 0, box, 0, -1, ctx).ok)
	assert_eq(ctx.wallet.get_gold(), 40)
	assert_true(box.is_empty(), "consumed")
	_put(box, 0, wood, 1)
	assert_eq(box.check_remove(0, 1, ctx).hint, InvDropCheck.LOCKED, "no buyback")


func test_sell_box_rejects_unsellable_unless_allowed() -> void:
	var box := _box(InvSellBoxPolicy.Payment.IMMEDIATE)
	var inv := _c(1)
	_put(inv, 0, junk, 3)
	var ctx := _ctx(0)
	assert_eq(InvTransfer.move(inv, 0, box, 0, -1, ctx).hint, InvDropCheck.WRONG_TYPE)
	(box.policy as InvSellBoxPolicy).accept_unsellable = true
	assert_true(InvTransfer.move(inv, 0, box, 0, -1, ctx).ok)
	assert_eq(ctx.wallet.get_gold(), 0)


func test_shipping_bin_defers_payment_until_settle() -> void:
	var bin := _box(InvSellBoxPolicy.Payment.DEFERRED)
	var p := bin.policy as InvSellBoxPolicy
	var inv := _c(2)
	_put(inv, 0, wood, 10)
	_put(inv, 1, hoe, 1)
	var ctx := _ctx(0)
	assert_eq(InvTransfer.move(inv, 0, bin, 0, -1, ctx).hint, InvDropCheck.SELL)
	assert_true(InvTransfer.move(inv, 1, bin, 1, -1, ctx).ok)
	assert_eq(ctx.wallet.get_gold(), 0, "nothing yet")
	assert_eq(p.pending_value(bin, ctx), 60)
	# Take the hoe back out: free, no gold involved.
	assert_true(InvTransfer.move(bin, 1, inv, 1, -1, ctx).ok)
	assert_eq(p.pending_value(bin, ctx), 20)
	assert_eq(p.settle(bin, ctx.wallet, ctx), 20)
	assert_eq(ctx.wallet.get_gold(), 20)
	assert_true(bin.is_empty())
	assert_eq(p.settle(bin, ctx.wallet, ctx), 0)


func test_sell_via_held_stack_and_quick_move() -> void:
	var box := _box(InvSellBoxPolicy.Payment.IMMEDIATE, true, false, 4)
	var inv := _c(2)
	_put(inv, 0, wood, 10)
	_put(inv, 1, hoe, 1)
	var ctx := _ctx(0)
	var h := InvHeldStack.new()
	h.pickup(inv, 0, -1, ctx)
	assert_eq(h.place_one(box, 0, ctx).hint, InvDropCheck.SELL)
	assert_eq(ctx.wallet.get_gold(), 2)
	assert_eq(h.count(), 9)
	h.return_home(ctx)
	var oc := InvOpenContext.new()
	ctx.open_context = oc
	oc.open(inv)
	oc.open(box, &"external")
	var r := oc.quick_move(inv, 1, -1, ctx)
	assert_true(r.ok)
	assert_eq(r.hint, InvDropCheck.SELL)
	assert_eq(ctx.wallet.get_gold(), 42)


func test_sell_box_caption_and_swap_block() -> void:
	var box := _box(InvSellBoxPolicy.Payment.IMMEDIATE)
	var p := box.policy as InvSellBoxPolicy
	var inv := _c(1)
	_put(inv, 0, wood, 3)
	_put(box, 0, hoe, 1)
	var ctx := _ctx(100)
	assert_eq(p.slot_caption(box, 0, ctx), "+40g")
	assert_eq(p.slot_caption(box, 1, ctx), "")
	assert_eq(InvTransfer.move(inv, 0, box, 0, -1, ctx).hint, InvDropCheck.SWAP_BLOCKED)
