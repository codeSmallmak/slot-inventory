# 11 · Signals cheatsheet

| Where | Signal | Use for |
|---|---|---|
| `InvContainer` | `slot_changed(i)` | redraw, custom views |
| | `item_added(def, count)` / `item_removed(def, count)` | quests ("collect 10 wood"), stats, sounds |
| | `transaction_committed(result)` | log, achievements; `result.hint` = place/merge/swap/buy/sell |
| `InvUISession` | `transfer_committed(result)` / `transfer_rejected(result)` | click / error sounds |
| | `drop_outside_requested(held)` | spawn a world pickup |
| | `hover_changed(view)` | custom info panels |
| `InvHeldStack` | `changed` | cursor visuals |
| `InvHotbar` | `selection_changed(i)` | UI |
| | `active_changed(i, stack)` | what the player holds (fires on select, count change, data change) |
| `InvEquipment` | `equipped(type, def)` / `unequipped(type, def)` | apply/remove stats, swap meshes |
| `InvWallet` | `changed(gold)` | gold label |
| `InvOpenContext` | `container_opened` / `container_closed` | UI show/hide |

Results (`InvTransferResult`): `ok`, `hint`, `moved_count`, `remainder`, `swapped`, `from`, `from_index`, `to`, `to_index`, `def`.

## Common one-liners
```gdscript
inventory.has_at_least(&"wood", 5)
inventory.consume(&"wood", 5)                  # bool, all-or-nothing
inventory.add_auto(stack)                      # returns leftover stack
inventory.count_of(&"wood")
inventory.find(&"axe")                         # slot index or -1
InvTransfer.move(a, i, b, j)                   # programmatic move, same rules as the player
InvTransfer.move_auto(a, i, b)                 # "put this anywhere in b"
```
