# 07 · Save / load

```gdscript
var save := InvSaveState.new()
save.register(&"inventory", inventory)
save.register(&"hotbar", hotbar)
save.register(&"equipment", eq.container)
save.register(&"chest_barn", barn_chest)
save.register_hotbar(&"hotbar", hotbar_sel)   # selected slot
save.wallet = wallet
save.extra = {"day": 12}                       # any JSON-safe game data

# save
$Session.return_held()                         # cursor item back first
save.save_to_file("user://slot0.json")

# load
var report := save.load_from_file("user://slot0.json", db)
```
Don't register shops (they regenerate). Register chests by a stable id.

## What the load report says
`report.ok` · `report.missing_ids` (items removed from the game; skipped) · `report.dropped` (units that no longer fit because a container shrank) · `report.unknown_containers` (in the file, not registered; ignored).

Containers keep their CURRENT size. Grew → fine. Shrank → overflow is re-added with `add_auto`, the rest is `dropped`.

## Inside your own save file
```gdscript
my_save["inventory"] = save.to_dict()
save.from_dict(my_save["inventory"], db)
```

## Ints become floats
JSON does that. `int(stack.data["uses"])` when reading, or `save_to_file(path, false)` / `load_from_file(path, db, false)` for Godot's binary format (keeps types, not human-readable).

## Rules
- Never rename an item `id` after players have saves. Add a new def instead.
- Component `data` must stay JSON-safe: numbers, strings, bools, arrays, dicts. No Objects, no Vector2 (use `[x, y]`).
