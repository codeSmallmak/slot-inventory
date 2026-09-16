# 02 · Items and icons

## Item def fields
| Field | Use |
|---|---|
| `id` | Unique. Used in code and save files. Never rename after shipping. |
| `display_name`, `description` | Tooltip. |
| `icon` | Any `Texture2D`. |
| `max_stack` | 1 = unstackable. |
| `tags` | Free-form: `tool`, `seed`, `sellable`. Filters and sorting use them. |
| `equip_type` | `head`, `hand`… Empty = not equippable. |
| `price`, `sell_price` | Shops. 0 = not for sale / worthless. |
| `components` | Behaviour + per-stack state (see 04). |

## Icon from a PNG
Drag the PNG onto **Icon**. Pixel art: select the PNG → Import dock → Filter **Nearest** → Reimport.

## Icon from a 3D model (no Blender)
1. Models (`.glb` / `.gltf` / `.tscn`) under `res://models/`.
2. Open `addons/slot_inventory/tools/bake_icons.gd`.
3. Ctrl+Shift+X (File → Run). PNGs appear in `res://icons/`, one per model.
4. Change `SIZE`, `YAW`, `PITCH`, `MARGIN` at the top of that file and re-run to adjust.

At runtime instead:
```gdscript
var baker := InvIconBaker.new(); add_child(baker)
def.icon = await baker.bake_scene(load("res://models/axe.glb"))
# or everything without an icon:
await baker.bake_missing_icons(db, func(d): return load("res://models/%s.glb" % d.id))
```

## Making stacks
```gdscript
db.make_stack(&"axe")            # 1, components initialised
db.make_stack(&"wood", 30)
db.get_def(&"axe")               # null if unknown
```
