# 06 · Shops and selling

## Wallet
```gdscript
var wallet := InvWallet.new(250)            # or any object with get_gold() / try_spend(n) / add_gold(n)
$Session.set_wallet(wallet)
wallet.changed.connect(func(g): gold_label.text = str(g))
```

## Shop (buying)
UI: in your inventory UI scene add a `Container` with `inv_container_view.gd`, name it `ShopGrid`, set **Group** = `external`, **Columns** = 4.

```gdscript
var shop := InvContainer.new(4, &"shop")
shop.policy = InvShopPolicy.new()               # infinite_stock = true by default
shop.set_stack(0, db.make_stack(&"seed", 99))   # what's on display (count = shown stack)

func open_shop():
    $ShopGrid.bind(shop)
    $Session.register($ShopGrid)
```
Player gestures on a shop slot: click = buy 1 to cursor · Shift = 5 · Ctrl = 10 · Ctrl+Shift = 25 · hold = repeat, accelerating. Shift-click-style quick-move buys straight into the inventory. Funds cap the amount (want 10, afford 7 → get 7). Nothing can be placed into a shop.

Prices: `def.price × policy.price_multiplier`, or override `unit_price(def, ctx)`. Set `infinite_stock = false` for limited stock. Slots show the price; tooltips say "Buy: 10g" in red when unaffordable.

## Sell counter (paid now)
UI: another `Container` + `inv_container_view.gd`, **Group** = `external`. Bind and register it like the shop.
```gdscript
var counter := InvContainer.new(4, &"counter")
counter.policy = InvSellBoxPolicy.new()     # payment IMMEDIATE, buyback true
```
Drop an item → gold in. Take it back → gold out (refused if you already spent it). `consume = true` makes items vanish on sale. `buyback = false` = no returns. Only items with `sell_price > 0` are accepted unless `accept_unsellable`.

## Shipping bin (paid later)
```gdscript
var bin_policy := InvSellBoxPolicy.new()
bin_policy.payment = InvSellBoxPolicy.Payment.DEFERRED
bin.policy = bin_policy
# end of day:
var earned := bin_policy.settle(bin, wallet)
bin_policy.pending_value(bin)               # for a "Ship (120g)" label
```

## Bulk settings
On the session: `bulk_shift`, `bulk_ctrl`, `bulk_both`, `hold_repeat_delay`, `hold_repeat_interval`, `hold_repeat_min`.
