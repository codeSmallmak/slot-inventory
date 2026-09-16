# 05 · Hotbar and equipment

## Hotbar
A hotbar = a normal `InvContainer` (so items drag into it) + an `InvHotbar` that tracks which slot is selected.

In your inventory UI scene (the one from guide 01): add a `Container` node, attach `addons/slot_inventory/ui/inv_hotbar_view.gd`, name it `HotbarGrid`, set **Columns** = 8.

In that scene's script:
```gdscript
var hotbar := InvContainer.new(8, &"hotbar")
var sel := InvHotbar.new(hotbar)

func _ready():
    $HotbarGrid.bind_hotbar(sel)             # draws slots + highlights the selected one
    $Session.register($HotbarGrid)           # items can be dragged into it
    sel.active_changed.connect(func(i, stack): player.hold(stack.def))
```
Input, in `_unhandled_input`:
```gdscript
if sel.handle_input(event): get_viewport().set_input_as_handled()
```
Uses `inv_hotbar_1..9`, `inv_hotbar_next/prev` if they exist in the InputMap; otherwise digit keys and mouse wheel. Turn off with `use_number_keys` / `use_wheel`.

`sel.active_stack()` · `sel.consume_active(n)` · `sel.use_active(player)` · `sel.select(i)` · `sel.select_next()`.

## Equipment (paper doll)
In your inventory UI scene:
1. Add a `Container` node, attach `inv_equipment_view.gd`, name it `Doll`, set **Group** = `equipment`.
2. Under `Doll`, add one `Control` per equipment slot, attach `inv_slot_view.gd` to each, and **name each one after its slot type**: `Head`, `Body`, `Hand`, `Ring`, `Ring2`.
3. Drag them into position in the 2D editor (over a character picture if you have one). Their positions are kept as-is.

In the scene's script:
```gdscript
var eq := InvEquipment.new([&"head", &"body", &"hand", &"ring", &"ring"])  # same names as the nodes

func _ready():
    $Doll.bind_equipment(eq)
    $Session.register($Doll)
    eq.equipped.connect(func(type, def): player.apply(def))
    eq.unequipped.connect(func(type, def): player.remove(def))
```
Slots accept only matching `equip_type`, one item each. Drag, shift-click, and `eq.equip(inventory, i)` all work; swapping onto an occupied slot swaps.

`eq.get_equipped_def(&"hand")` · `eq.is_equipped(&"ring", 1)` · `eq.unequip(&"head", inventory)`. Save `eq.container` like any container.
