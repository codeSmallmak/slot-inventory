# Slot Inventory (Godot 4.7)

Drop-in slot inventory: stacking, drag/drop, hotbar, chests, equipment, shops,
selling, tooltips, save/load. Game-agnostic. Re-theme without touching code.

## Install
1. Copy `addons/slot_inventory/` into your project. No plugin to enable.
2. Run `demo/inv_demo.tscn` to see everything working.

## How it fits together (30 seconds)
- **Data**: `InvItemDef` (static item) → `InvItemDatabase` (all defs) → `InvItemStack` (def + count + per-stack `data`).
- **Containers**: `InvContainer` = fixed slots. Rules on it: `InvSlotFilter` per slot, `InvContainerPolicy` per container.
- **Movement**: everything goes through `InvTransfer`. It validates, then commits, or changes nothing.
- **Cursor**: `InvHeldStack`. Pick up / place / swap are transfers too.
- **UI**: `InvContainerView` (grid) + `InvSlotView` (one slot) + `InvCursorView` + `InvTooltipView`. They only draw.
- **Input**: `InvUISession` turns clicks/keys/gamepad into transfers. The only place gestures are interpreted.
- **Extras**: `InvHotbar`, `InvEquipment`, `InvSorter`, `InvShopPolicy`, `InvSellBoxPolicy`, `InvWallet`, `InvSaveState`, `InvUsableComponent`, `InvIconBaker`.

## Guides (docs/)
1. `01_first_inventory.md` — items, a container, a grid on screen, drag and drop
2. `02_items_and_icons.md` — defs, database, icons, bake icons from 3D models
3. `03_containers_filters_policies.md` — chests, filtered slots, locked slots, custom rules
4. `04_components_and_use.md` — durability, water levels, food, placeables, "press E to use"
5. `05_hotbar_and_equipment.md` — selection, number keys, paper doll
6. `06_shops_and_selling.md` — buying with bulk/hold, sell counter, shipping bin, your own wallet
7. `07_save_load.md` — one call to save, one to load, what survives version changes
8. `08_tooltips.md` — choose what a tooltip shows, per screen, no code
9. `09_theming.md` — swap the look with a Theme resource
10. `10_input_and_controller.md` — gestures, InputMap actions, gamepad
11. `11_signals_cheatsheet.md` — what to connect to for sounds, quests, stats

## Tests
`tests/` runs in the editor with the godot-ai test runner (`McpTestSuite`). 175+ tests, headless.
