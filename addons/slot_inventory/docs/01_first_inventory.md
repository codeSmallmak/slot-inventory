# 01 · Your first inventory (5 minutes)

End result: an inventory grid on screen, filled with items, drag and drop working.

You will make three things:
1. Item definitions (what items exist).
2. An inventory UI scene (the grid you see).
3. A short script that fills the grid with items.

---

## Step 1 · Make your items

Each item is a small resource file.

1. In the **FileSystem** dock, right-click any folder → **Create New → Resource…**
2. In the search box type `InvItemDef`, select it, click **Create**.
3. Save it as `res://items/wood.tres`.
4. Click it. In the **Inspector** set:
   - **Id** → `wood` (must be unique; used in code and save files)
   - **Display Name** → `Wood`
   - **Max Stack** → `50`
   - **Icon** → drag a PNG onto the field
5. Repeat steps 1–4 for each item.

Now make the list of all items:

6. Right-click the folder → **Create New → Resource…** → `InvItemDatabase` → save as `res://items/items.tres`.
7. Click it. In the Inspector expand **Items**, click **Add Element** once per item, drag each item `.tres` into a slot.

You now have `items.tres` = the list of every item in your game.

---

## Step 2 · Make the inventory UI scene

This is a new, separate scene: the inventory window. You'll add it to your game's UI later (or run it on its own to test).

1. **Scene → New Scene**. Choose **User Interface** as the root type. Rename the root to `InventoryUI`.
2. Add these children to `InventoryUI` (right-click → **Add Child Node**, pick the type, then drag the script from `addons/slot_inventory/ui/` onto the node):

| Node name | Type to pick | Script to attach | Then set |
|---|---|---|---|
| `Session` | `Node` | `inv_ui_session.gd` | nothing |
| `Grid` | `Container` | `inv_container_view.gd` | Inspector → **Columns** = `5` |
| `Cursor` | `Control` | `inv_cursor_view.gd` | nothing |
| `Tooltip` | `PanelContainer` | `inv_tooltip_view.gd` | nothing (optional) |

3. Click `InventoryUI`. In the Inspector find **Theme** → drag in `addons/slot_inventory/ui/inv_default_theme.tres`.
4. Save the scene as `res://ui/inventory_ui.tscn`.

The grid is empty in the editor. That's normal: items are added by script when the game runs.
(Optional: set **Preview Slots** = 20 on `Grid` to see placeholder slots while you lay things out.)

---

## Step 3 · Fill it with items

1. Click `InventoryUI` → **Attach Script** → save as `res://ui/inventory_ui.gd`.
2. Replace its contents with:

```gdscript
extends Control

var db: InvItemDatabase = load("res://items/items.tres")   # your item list from Step 1
var inventory := InvContainer.new(20, &"inventory")         # 20 slots of data

func _ready() -> void:
    inventory.set_stack(0, db.make_stack(&"wood", 12))     # put 12 wood in slot 0
    $Grid.bind(inventory)                                   # grid shows this container
    $Session.set_cursor($Cursor)
    $Session.set_tooltip($Tooltip)                          # delete this line if you skipped Tooltip
    $Session.register($Grid)                                # clicks on the grid now do things
```

3. Press **F6** (run current scene).

Click an item to pick it up, click a slot to put it down, drag to move, right-click to split. Hover for a tooltip.

---

## Step 4 · Put it in your game

Instance `inventory_ui.tscn` wherever your HUD lives (a `CanvasLayer` is typical). Toggle its `visible` on your inventory key. Give the `inventory` variable to the rest of your game (an autoload, or your player script) so pickups can call:

```gdscript
var leftover := inventory.add_auto(db.make_stack(&"wood", 5))  # fills existing stacks first
if not leftover.is_empty():
    drop_on_ground(leftover)                                     # inventory was full
```

Other calls you'll use immediately:
```gdscript
inventory.count_of(&"wood")            # how many
inventory.has_at_least(&"wood", 3)     # bool
inventory.consume(&"wood", 3)          # remove 3 across slots; false (and nothing removed) if short
```

---

## Step 5 · Add a chest

In `inventory_ui.tscn`, add another `Container` with `inv_container_view.gd`, name it `ChestGrid`, set **Columns** = 4, and set its **Group** = `external`.

```gdscript
var chest := InvContainer.new(12, &"chest")   # one per chest in your world, kept by the game

func open_chest(c: InvContainer) -> void:
    $ChestGrid.bind(c)
    $Session.register($ChestGrid)

func close_chest() -> void:
    $Session.return_held()                     # item on the cursor goes back where it came from
    $Session.unregister($ChestGrid)
```

With a chest open: Shift-click moves an item to the other side, double-click gathers matching stacks.

---

## Next
- `02_items_and_icons.md` — icons from 3D models, item fields explained
- `05_hotbar_and_equipment.md` — hotbar with number keys
- `07_save_load.md` — one call to save everything
