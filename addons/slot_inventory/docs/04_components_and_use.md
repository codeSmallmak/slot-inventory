# 04 · Components: durability, water, food, placeables, "press E"

A component = a Resource on `def.components`. Shared per item type.
Per-stack state goes in `stack.data[data_key]` and MUST be JSON-safe (numbers, strings, bools, arrays, dicts). It saves automatically.

## Hooks (override what you need)
| Hook | When |
|---|---|
| `init_data(stack)` | New stack created. Set defaults. |
| `can_merge(a, b)` | Return false → never stacks (durability). |
| `merge(target, incoming)` | Combine state (average freshness). |
| `split(source, new)` | Divide state. Default copies. |
| `tick(stack, delta, modifier)` | Time. Return true if changed. |
| `get_overlay_info(stack)` | `{"bar": 0.4, "bar_color": Color, "tint": Color}` on the slot. |
| `get_tooltip_lines(stack)` | Strings or `{"text","style"}`. |

## Durability
```gdscript
class_name Durability extends InvItemComponent
func _init(): data_key = &"dur"
func init_data(s): s.data[data_key] = 1.0
func can_merge(_a, _b): return false
func get_overlay_info(s): return {"bar": s.data[data_key]}
func get_tooltip_lines(s): return ["Durability: %d%%" % int(s.data[data_key] * 100)]
```
Damage it: `stack.data[&"dur"] -= 0.1; container.touch(i)` — `touch` redraws.

## Usable items — one pattern for food, cans, seeds, placeables
Extend `InvUsableComponent`, implement `use()`, return one of:
`CONSUME` (remove one), `CHANGED` (data changed, keep it), `FAILED` (refuse), `NOOP`.

```gdscript
class_name Food extends InvUsableComponent
@export var restores := 25
func can_use(_s, user, _c): return user.hunger < 100
func use(_s, user, _c):
    user.hunger = min(user.hunger + restores, 100)
    return CONSUME
```
```gdscript
class_name WateringCan extends InvUsableComponent
@export var capacity := 8
func _init(): data_key = &"water"
func init_data(s): s.data[data_key] = capacity
func can_merge(_a, _b): return false
func get_overlay_info(s): return {"bar": float(s.data[data_key]) / capacity, "bar_color": Color.SKY_BLUE}
func use(s, _user, _c):
    if int(s.data[data_key]) <= 0: return FAILED
    s.data[data_key] = int(s.data[data_key]) - 1
    return CHANGED
```
```gdscript
class_name Placeable extends InvUsableComponent
@export var scene: PackedScene
@export var rule: PlacementRule           # your Resource: snap, valid ground, overlap
func use(_s, user, _c):
    var cell = user.aim_cell()
    if not rule.ok(user.world, cell): return FAILED
    var node = scene.instantiate(); user.world.add_child(node); node.global_position = cell
    return CONSUME
```

## Trigger it
```gdscript
# hotbar (press E):
var r := hotbar.use_active(player)          # returns CONSUME/CHANGED/NOOP/FAILED
# any slot (right-click food in the bag):
InvUsableComponent.use_slot(inventory, i, player)
# prompt text:
var u := hotbar.active_usable(); label.text = u.use_label if u else ""
```
The slot's policy is checked first (locked slot → FAILED, effect never runs). `player` is whatever you pass; the addon never reads it.

## Read `data` after a load
JSON turns ints into floats. Use `int(s.data[&"water"])`. Or save binary (see 07).
