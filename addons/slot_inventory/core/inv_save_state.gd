@tool
class_name InvSaveState
extends RefCounted

## Snapshots a set of containers (plus wallet and hotbar selections) into one
## JSON-safe Dictionary and restores it. Register what should persist —
## player inventory, hotbar, equipment.container, chests — and leave shops
## and other regenerating containers out.
##
##   var save := InvSaveState.new()
##   save.register(&"inventory", inventory)
##   save.register(&"hotbar", hotbar)
##   save.register(&"equipment", equipment.container)
##   save.register_hotbar(&"hotbar", hotbar_sel)
##   save.wallet = wallet
##   save.save_to_file("user://slot0.json")
##   ...
##   var report := save.load_from_file("user://slot0.json", db)
##
## Return the held stack (InvUISession.return_held) before saving; the
## cursor is not persisted.
##
## Restoring tolerates change: a container that grew or shrank since the
## save keeps its current size (overflow items are re-added with add_auto,
## anything that still doesn't fit is counted in report.dropped), unknown
## item ids are skipped and listed in report.missing_ids, and containers in
## the save that are no longer registered are ignored.
##
## JSON turns every number into a float; InvItemStack.from_dict restores
## count as int, but component data that stores ints will come back as
## floats. Components should read their data with int()/float() as needed,
## or use the binary format (save_to_file(path, false)).

const FORMAT_VERSION := 1

var wallet: Object = null
## Free-form game data saved alongside (day, weather...). Must be JSON-safe.
var extra: Dictionary = {}

var _containers: Dictionary = {}  # StringName -> InvContainer
var _hotbars: Dictionary = {}     # StringName -> InvHotbar


# ------------------------------------------------------------- registration

func register(id: StringName, c: InvContainer) -> void:
	if c == null:
		_containers.erase(id)
	else:
		_containers[id] = c


func unregister(id: StringName) -> void:
	_containers.erase(id)


func register_hotbar(id: StringName, h: InvHotbar) -> void:
	if h == null:
		_hotbars.erase(id)
	else:
		_hotbars[id] = h


func registered_ids() -> Array:
	return _containers.keys()


# --------------------------------------------------------------- snapshot

func to_dict() -> Dictionary:
	var containers := {}
	for id in _containers:
		containers[String(id)] = (_containers[id] as InvContainer).to_array()
	var hotbars := {}
	for id in _hotbars:
		hotbars[String(id)] = (_hotbars[id] as InvHotbar).selected
	var d := {
		"version": FORMAT_VERSION,
		"containers": containers,
		"hotbars": hotbars,
		"extra": extra.duplicate(true),
	}
	if wallet != null:
		d["gold"] = InvWallet.gold_of(wallet)
	return d


## Restore. Returns a report: {"ok": bool, "version": int,
## "missing_ids": Array[String], "dropped": int, "unknown_containers": Array}.
func from_dict(d: Dictionary, db: InvItemDatabase) -> Dictionary:
	var report := {"ok": true, "version": int(d.get("version", 0)), "missing_ids": [], "dropped": 0, "unknown_containers": []}
	if db == null:
		report["ok"] = false
		return report
	var containers: Dictionary = d.get("containers", {})
	for key in containers:
		var id := StringName(str(key))
		if not _containers.has(id):
			report["unknown_containers"].append(str(key))
			continue
		var arr: Variant = containers[key]
		if not arr is Array:
			continue
		report["dropped"] += _apply_slots(_containers[id], arr, db, report["missing_ids"])
	var hotbars: Dictionary = d.get("hotbars", {})
	for key in hotbars:
		var id := StringName(str(key))
		if _hotbars.has(id):
			(_hotbars[id] as InvHotbar).select(int(hotbars[key]))
	if wallet != null and d.has("gold"):
		_set_gold(wallet, int(d["gold"]))
	var ex: Variant = d.get("extra", {})
	extra = ex.duplicate(true) if ex is Dictionary else {}
	return report


# ------------------------------------------------------------------- files

func to_json(indent: String = "\t") -> String:
	return JSON.stringify(to_dict(), indent)


func from_json(text: String, db: InvItemDatabase) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK or not j.data is Dictionary:
		var msg := j.get_error_message() if j.get_error_message() != "" else "not a JSON object"
		return {"ok": false, "version": 0, "missing_ids": [], "dropped": 0, "unknown_containers": [], "error": "invalid JSON: %s (line %d)" % [msg, j.get_error_line()]}
	return from_dict(j.data, db)


## Write the snapshot. json=false uses Godot's binary Variant format, which
## keeps ints as ints. Returns OK or the FileAccess error.
func save_to_file(path: String, json: bool = true) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	if json:
		f.store_string(to_json())
	else:
		f.store_var(to_dict())
	f.close()
	return OK


## Read and restore. The report gains "error" when the file is unreadable.
func load_from_file(path: String, db: InvItemDatabase, json: bool = true) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "version": 0, "missing_ids": [], "dropped": 0, "unknown_containers": [], "error": error_string(FileAccess.get_open_error())}
	var report: Dictionary
	if json:
		report = from_json(f.get_as_text(), db)
	else:
		var v: Variant = f.get_var()
		report = from_dict(v, db) if v is Dictionary else {"ok": false, "version": 0, "missing_ids": [], "dropped": 0, "unknown_containers": [], "error": "invalid data"}
	f.close()
	return report


# ---------------------------------------------------------------- internals

## Load `arr` into `c` keeping c's current size. Returns units dropped.
func _apply_slots(c: InvContainer, arr: Array, db: InvItemDatabase, missing: Array) -> int:
	var stacks: Array[InvItemStack] = []
	for v in arr:
		var d: Dictionary = v if v is Dictionary else {}
		if not d.is_empty():
			var id := str(d.get("id", ""))
			if not db.has(StringName(id)):
				if not missing.has(id):
					missing.append(id)
				stacks.append(InvItemStack.new())
				continue
		stacks.append(InvItemStack.from_dict(d, db))
	c.clear_all()
	var dropped := 0
	var n := mini(stacks.size(), c.size())
	for i in n:
		c.set_stack(i, stacks[i])
	for i in range(n, stacks.size()):
		var s := stacks[i]
		if s.is_empty():
			continue
		var rem := c.add_auto(s)
		dropped += rem.count
	return dropped


static func _set_gold(w: Object, gold: int) -> void:
	if w.has_method("set_gold"):
		w.call("set_gold", gold)
		return
	# Generic wallet: adjust by difference.
	var cur := InvWallet.gold_of(w)
	if gold > cur:
		InvWallet.add_to(w, gold - cur)
	elif gold < cur:
		InvWallet.spend_from(w, cur - gold)
