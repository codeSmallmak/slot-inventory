@tool
class_name InvContainerPolicy
extends Resource

## Container-wide rule hook. Shops, sell boxes, shipping bins, locked chests
## are all policies. Base class allows everything and does nothing on commit.
##
## Policies are shared Resources: never store per-container runtime state
## here. Runtime dependencies (wallet, open containers, clock) arrive via
## the InvTransferContext passed to every hook.

## True when on_commit has external effects (gold, quest flags...). Transfer
## refuses SWAPS involving such containers, because a swap would be two
## side-effecting transactions in one step.
@export var has_side_effects: bool = false


## May `stack` (the units about to arrive) enter slot `index`?
## Return a custom positive hint (e.g. InvDropCheck.SELL) to drive UI.
func can_insert(_container: InvContainer, _index: int, _stack: InvItemStack, _ctx: InvTransferContext) -> InvDropCheck:
	return InvDropCheck.accept()


## May `amount` units leave slot `index`?
func can_remove(_container: InvContainer, _index: int, _amount: int, _ctx: InvTransferContext) -> InvDropCheck:
	return InvDropCheck.accept()


## Called once after a transfer touching this container has been committed.
## `role` is &"source" or &"target" (a container can be both on same-container moves).
func on_commit(_container: InvContainer, _role: StringName, _result: InvTransferResult, _ctx: InvTransferContext) -> void:
	pass


## Swaps are refused for side-effecting policies (see has_side_effects).
func allows_swap() -> bool:
	return not has_side_effects


## Vendor-style pickup: the UI session treats LMB as "take N into the hand"
## with Shift/Ctrl bulk counts and hold-to-repeat, instead of the normal
## pick-up / quick-move / collect gestures. Shops return true.
func bulk_pickup_enabled() -> bool:
	return false


## Short text the slot view draws over the slot (price tag, "SOLD", ...).
## Empty = nothing.
func slot_caption(_container: InvContainer, _index: int, _ctx: InvTransferContext) -> String:
	return ""


## Tooltip lines about this slot from the policy's point of view ("Buy: 10g",
## "Sells for 2g", "Locked"). Strings or {"text","style"} Dictionaries.
func slot_tooltip_lines(_container: InvContainer, _index: int, _ctx: InvTransferContext) -> Array:
	return []
