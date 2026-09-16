@tool
class_name InvWallet
extends RefCounted

## Default currency holder. Games with their own economy can skip this and
## hand InvTransferContext.wallet any Object exposing the same three
## methods: get_gold() -> int, try_spend(int) -> bool, add_gold(int).

signal changed(gold: int)

var _gold: int = 0


func _init(start: int = 0) -> void:
	_gold = maxi(start, 0)


func get_gold() -> int:
	return _gold


func can_afford(amount: int) -> bool:
	return amount <= _gold


func try_spend(amount: int) -> bool:
	if amount < 0 or amount > _gold:
		return false
	if amount == 0:
		return true
	_gold -= amount
	changed.emit(_gold)
	return true


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	_gold += amount
	changed.emit(_gold)


func set_gold(amount: int) -> void:
	amount = maxi(amount, 0)
	if amount == _gold:
		return
	_gold = amount
	changed.emit(_gold)


## Duck-typed helper for policies: gold in any wallet-like object, 0 if none.
static func gold_of(w: Object) -> int:
	if w == null or not w.has_method("get_gold"):
		return 0
	return int(w.call("get_gold"))


static func spend_from(w: Object, amount: int) -> bool:
	if amount <= 0:
		return true
	if w == null or not w.has_method("try_spend"):
		return false
	return bool(w.call("try_spend", amount))


static func add_to(w: Object, amount: int) -> void:
	if amount <= 0 or w == null or not w.has_method("add_gold"):
		return
	w.call("add_gold", amount)


func _to_string() -> String:
	return "InvWallet(%dg)" % _gold
