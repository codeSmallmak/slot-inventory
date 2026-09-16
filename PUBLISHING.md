# Publishing Slot Inventory

## What ships
Only `addons/slot_inventory/`. Users copy that folder into their project.
`demo/` and `tests/` live in this repo for development and are optional extras.
`addons/godot_ai/` is a dev tool and is git-ignored; never ship it.

## Build the zip
1. In the FileSystem dock, right-click `addons/slot_inventory` → **Open in File Manager**.
2. Zip the folder so the archive contains `addons/slot_inventory/...` at its root
   (select the `slot_inventory` folder's parent `addons`, zip `addons` → rename to `slot_inventory_1.0.0.zip`).
3. Optionally add `demo/` next to `addons/` in the same zip.

## Version bump
- `addons/slot_inventory/plugin.cfg` → `version`
- Tag the git commit `v1.0.0`.

## Godot Asset Store (store.godotengine.org)
1. Create an account, log in, click **Upload Asset**.
2. Publisher: `smallmak` (or your name). Asset Name: `Slot Inventory`. Asset URL: `slot-inventory`.
3. **Settings**: summary (one line), description (paste README intro + guide list), tags
   (inventory, ui, rpg, farming, tools), type: Plugin/Addon, license: MIT,
   source link: your GitHub repo, AI disclosure: answer honestly.
4. **Media**: thumbnail = `addons/slot_inventory/icon.svg` exported to PNG (128×128 or larger),
   3–5 screenshots of the demo (run `demo/inv_demo.tscn`, Win+Shift+S), optional short video.
5. **Versions**: upload the zip, changelog "Initial release", Godot min `4.7`, max blank.
6. **Pricing**: free; add a donation link if you want.
7. **Submit**. It enters a review queue; you get an email with approval or the reason for rejection. Fix and resubmit.

## GitHub (do this first; the store asks for a source link)
1. Create a public repo `slot-inventory` (or similar).
2. In the project folder: `git init`, `git add .`, `git commit -m "Slot Inventory 1.0.0"`, push.
3. Create a Release `v1.0.0` and attach the same zip.

## Also worth doing
- itch.io: create a "Tool/Asset" project, upload the zip, link the docs. Same zip.
- Keep `docs/` and `README.md` inside `addons/slot_inventory/` so they travel with the folder.
