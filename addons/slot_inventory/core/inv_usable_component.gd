@tool
class_name InvUsableComponent
extends InvItemComponent

## Base for items the player USES from the hotbar or inventory: food,
## watering cans, seeds, placeables, potions. Subclass, override use(),
## return what should happen to the stack. The inventory does the bookkeeping
## (remove a unit / redraw / nothing); your game does the effect.
##
##   class FoodComponent extends InvUsableComponent:
##       @export var restores := {"hunger": 25}
##       func use(stack, user, ctx) -> StringName:
##           for k in restores: user.stats[k] += restores[k]
##           return CONSUME
##
## Then: hotbar.use_active(player)  or  InvUsableComponent.use_slot(inv, i, player)
##
## `user` is whatever your game passes (the player node, a controller, a
## Dictionary of stats) — the addon never looks inside it.

## use() results
const CONSUME := &"consume"   ## effect applied; remove one unit from the stack
const CHANGED := &"changed"   ## stack.data changed (water level...); redraw, keep the unit
const NOOP := &"noop"         ## nothing happened (not usable here)
const FAILED := &"failed"     ## refused (empty can, full stomach); UI may shake

## Verb for prompts/tooltips ("Eat", "Water", "Place").
@export var use_label: String = "Use"


## May the item be used right now? Default: yes. Override for "not while
## full", "only on soil" style checks; return false to skip use() entirely.
func can_use(_stack: InvItemStack, _user: Variant, _ctx: InvTransferContext) -> bool:
	return true


## Apply the effect. Return CONSUME / CHANGED / NOOP / FAILED.
func use(_stack: InvItemStack, _user: Variant, _ctx: InvTransferContext) -> StringName:
	return NOOP


# --------------------------------------------------------------- dispatch

## First usable component on a def, or null.
static func find(def: InvItemDef) -> InvUsableComponent:
	if def == null:
		return null
	return def.get_component(InvUsableComponent) as InvUsableComponent


## Use the item in container[i] on `user`. Handles the result:
##   CONSUME -> one unit removed
##   CHANGED -> container.touch(i) so views/tooltips/hotbar refresh
## The slot's policy is asked first (check_remove 1); a locked slot returns
## FAILED without calling use(). Returns NOOP when the slot is empty / has no
## usable component / can_use() says no.
static func use_slot(container: InvContainer, i: int, user: Variant, ctx: InvTransferContext = null) -> StringName:
	if container == null or not container.is_valid_index(i):
		return NOOP
	var s := container.get_stack(i)
	if s.is_empty():
		return NOOP
	var u := find(s.def)
	if u == null or not u.can_use(s, user, ctx):
		return NOOP
	# Validate removal BEFORE the effect so a locked slot can't hand out a
	# free meal. Items in a slot you can't take from can't be used either.
	var rc := container.check_remove(i, 1, ctx)
	if not rc.ok or rc.capacity < 1:
		return FAILED
	var r := u.use(s, user, ctx)
	match r:
		CONSUME:
			var od := s.def
			var oc := s.count
			s.split_off(1)
			container.notify_slot_mutated(i, od, oc)
		CHANGED:
			container.touch(i)
	return r
