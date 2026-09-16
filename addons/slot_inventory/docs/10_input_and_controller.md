# 10 · Input and controller

## Mouse / touch (touch = emulated mouse, on by default in Godot)
| Gesture | Normal slot | Shop slot |
|---|---|---|
| LMB | pick up all / place / swap | buy 1 to cursor |
| LMB drag, release elsewhere | place there | — |
| RMB | pick up half / place one | buy 1 |
| Shift+LMB | quick-move (routed) | buy 5 |
| Ctrl+LMB | — | buy 10 |
| Ctrl+Shift+LMB | — | buy 25 |
| Double-click (holding) | collect matching stacks | — |
| Hold LMB | — | repeat buy |
| LMB outside slots (holding) | `drop_outside_requested` | |

Toggles on the session: `drag_to_place`, `double_click_collects`, `drop_outside_enabled`, `shake_on_reject`, `show_accepts_glow`.

## Keyboard / gamepad
Slots are focusable; d-pad / arrows move between them (Godot's focus neighbours). Focus counts as hover: feedback, glow, tooltip, and the cursor snaps to the focused slot.

Add these to Project → Input Map (all optional):
| Action | Does | Fallback |
|---|---|---|
| `inv_primary` | LMB | `ui_accept` |
| `inv_secondary` | RMB | none |
| `inv_quick` | hold = quick-move / bulk | Shift key |
| `inv_collect` | collect | none |
| `inv_hotbar_1`…`inv_hotbar_9` | select hotbar slot | digit keys |
| `inv_hotbar_next` / `inv_hotbar_prev` | cycle | mouse wheel |

## Quick-move routing
Source group → other groups in open order → same group. Inside that: merge targets first, then containers with a filter that accepts the item, then the rest. Override per group:
```gdscript
$Session.open.set_route(&"player", [&"equipment", &"external"])
```

## Drop in the world
```gdscript
$Session.drop_outside_requested.connect(func(held):
    var stack := held.take()          # or ignore to keep it on the cursor
    spawn_pickup(stack, player.position))
```
