# 03 · Containers, filters, policies

## Container
```gdscript
var c := InvContainer.new(12, &"chest")
c.get_stack(i)          # live InvItemStack, never null; .is_empty()
c.set_stack(i, stack)   # bypasses rules (loot gen, cheats). Emits signals.
c.set_slot_max(i, 10)   # cap this slot below def.max_stack
c.tick_modifier = 0.5   # fridge: components tick at half speed
c.tick(delta)           # advance spoilage/fuel components
```

## Only tools in this slot (filter)
```gdscript
var f := InvSlotFilter.new()
f.required_tags = [&"tool"]      # also: blocked_tags, equip_type, allowed_ids
c.set_filter(3, f)               # or c.set_all_filters(f)
```
Filtered containers are preferred by quick-move: shift-clicking a tool sends it to the toolbox before a plain chest.

## Locked / custom rules (policy)
Policies are Resources on `container.policy`. Override what you need:
```gdscript
class_name LockedRow extends InvContainerPolicy
func can_remove(c, i, amount, ctx) -> InvDropCheck:
    return InvDropCheck.reject(InvDropCheck.LOCKED) if i >= 4 else InvDropCheck.accept()
```
Hooks: `can_insert`, `can_remove` (return `accept(hint, capacity)` to cap or relabel), `on_commit` (after a transfer touched this container), `slot_caption` (text over the slot), `slot_tooltip_lines`, `bulk_pickup_enabled` (shop-style gestures).

Set `has_side_effects = true` if `on_commit` does anything external (gold, quests). Swaps are refused for those containers.

## Sorting
```gdscript
InvSorter.sort(c)        # merge + order (tag, id, count). Custom: sort(c, ctx, my_less)
InvSorter.compact(c)     # merge + pack, keep order
```
Both are all-or-nothing and respect filters, slot caps and locked slots.

## Hints you'll see
`place merge swap buy sell` (ok) · `full wrong_type locked empty no_funds swap_blocked` (refused). Every `InvDropCheck` / `InvTransferResult` carries one. Drive UI/sounds off them, don't re-derive rules.
