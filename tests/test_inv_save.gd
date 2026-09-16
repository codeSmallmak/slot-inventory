@tool
extends McpTestSuite

## Save/load: InvSaveState round trips (dict, JSON, binary file), size
## changes between save and load, unknown ids, wallet and hotbar state,
## component data survival.


class FreshnessComponent extends InvItemComponent:
	func _init() -> void:
		data_key = &"fresh"
	func init_data(stack: InvItemStack) -> void:
		stack.data[data_key] = 1.0
	func can_merge(a: InvItemStack, b: InvItemStack) -> bool:
		return is_equal_approx(float(a.data.get(data_key, 1.0)), float(b.data.get(data_key, 1.0)))


var db: InvItemDatabase
var wood: InvItemDef
var berry: InvItemDef
var hat: InvItemDef


func suite_name() -> String:
	return "inv_save"


func suite_setup(_ctx: Dictionary) -> void:
	db = InvItemDatabase.new()
	wood = _def(&"wood", 50)
	berry = _def(&"berry", 20, [FreshnessComponent.new()])
	hat = _def(&"hat", 1, [], &"head")


func _def(id: StringName, max_stack: int, comps: Array = [], equip: StringName = &"") -> InvItemDef:
	var d := InvItemDef.new()
	d.id = id
	d.max_stack = max_stack
	d.equip_type = equip
	var c: Array[InvItemComponent] = []
	for x in comps:
		c.append(x)
	d.components = c
	db.register(d)
	return d


func _put(c: InvContainer, i: int, def: InvItemDef, n: int) -> void:
	c.set_stack(i, InvItemStack.make(def, n))


func _ids(c: InvContainer) -> Array:
	var out := []
	for i in c.size():
		var s := c.get_stack(i)
		out.append("" if s.is_empty() else "%s:%d" % [s.def.id, s.count])
	return out


## A populated world: inventory, hotbar (+selection), equipment, wallet.
func _world() -> Dictionary:
	var inv := InvContainer.new(6, &"inventory")
	_put(inv, 0, wood, 12)
	var b := InvItemStack.make(berry, 5)
	b.data[&"fresh"] = 0.6
	inv.set_stack(2, b)
	_put(inv, 5, hat, 1)
	var hb := InvContainer.new(4, &"hotbar")
	_put(hb, 1, wood, 3)
	var sel := InvHotbar.new(hb)
	sel.select(1)
	var eq := InvEquipment.new([&"head", &"hand"])
	eq.equip(inv, 5)
	var w := InvWallet.new(340)
	var save := InvSaveState.new()
	save.register(&"inventory", inv)
	save.register(&"hotbar", hb)
	save.register(&"equipment", eq.container)
	save.register_hotbar(&"hotbar", sel)
	save.wallet = w
	save.extra = {"day": 12, "weather": "rain"}
	return {"inv": inv, "hb": hb, "sel": sel, "eq": eq, "w": w, "save": save}


## Same structure, empty, ready to be loaded into.
func _fresh_world() -> Dictionary:
	var inv := InvContainer.new(6, &"inventory")
	var hb := InvContainer.new(4, &"hotbar")
	var sel := InvHotbar.new(hb)
	var eq := InvEquipment.new([&"head", &"hand"])
	var w := InvWallet.new(0)
	var save := InvSaveState.new()
	save.register(&"inventory", inv)
	save.register(&"hotbar", hb)
	save.register(&"equipment", eq.container)
	save.register_hotbar(&"hotbar", sel)
	save.wallet = w
	return {"inv": inv, "hb": hb, "sel": sel, "eq": eq, "w": w, "save": save}


# ------------------------------------------------------------------- dict

func test_to_dict_shape() -> void:
	var wd := _world()
	var d: Dictionary = wd["save"].to_dict()
	assert_eq(d["version"], InvSaveState.FORMAT_VERSION)
	assert_eq(d["gold"], 340)
	assert_eq(d["hotbars"]["hotbar"], 1)
	assert_eq(d["extra"]["day"], 12)
	assert_eq((d["containers"]["inventory"] as Array).size(), 6)
	assert_eq(d["containers"]["inventory"][0]["id"], "wood")
	assert_eq(d["containers"]["inventory"][0]["count"], 12)
	assert_eq(d["containers"]["inventory"][1], {})
	assert_eq(d["containers"]["equipment"][0]["id"], "hat")
	assert_eq(wd["save"].registered_ids().size(), 3)


func test_round_trip_dict() -> void:
	var a := _world()
	var b := _fresh_world()
	var report: Dictionary = b["save"].from_dict(a["save"].to_dict(), db)
	assert_true(report["ok"])
	assert_eq(report["dropped"], 0)
	assert_eq(report["missing_ids"], [])
	assert_eq(_ids(b["inv"]), _ids(a["inv"]))
	assert_eq(_ids(b["hb"]), _ids(a["hb"]))
	assert_eq(b["eq"].get_equipped_def(&"head"), hat)
	assert_eq(b["sel"].selected, 1)
	assert_eq(b["w"].get_gold(), 340)
	assert_eq(b["save"].extra, {"day": 12, "weather": "rain"})
	assert_eq(b["inv"].get_stack(2).data[&"fresh"], 0.6, "component data restored")


func test_round_trip_json_string() -> void:
	var a := _world()
	var b := _fresh_world()
	var text: String = a["save"].to_json()
	assert_contains(text, "\"wood\"")
	var report: Dictionary = b["save"].from_json(text, db)
	assert_true(report["ok"])
	assert_eq(_ids(b["inv"]), _ids(a["inv"]))
	assert_eq(b["inv"].get_stack(0).count, 12, "count is an int again")
	assert_true(is_equal_approx(float(b["inv"].get_stack(2).data["fresh"]), 0.6))
	assert_eq(b["w"].get_gold(), 340)
	assert_eq(b["sel"].selected, 1)
	var bad: Dictionary = b["save"].from_json("not json", db)
	assert_false(bad["ok"])


func test_hotbar_signal_fires_on_load() -> void:
	var a := _world()
	var b := _fresh_world()
	var got := []
	b["sel"].active_changed.connect(func(i: int, s: InvItemStack) -> void: got.append([i, s.count]))
	b["save"].from_dict(a["save"].to_dict(), db)
	# select(1) fires with the (then still empty) slot, then the slot fills.
	assert_true(got.size() >= 1)
	assert_eq(got[-1], [1, 3])


# --------------------------------------------------------- shape changes

func test_container_grew_since_save() -> void:
	var a := _world()
	var b := _fresh_world()
	b["inv"].resize(10)
	var report: Dictionary = b["save"].from_dict(a["save"].to_dict(), db)
	assert_eq(report["dropped"], 0)
	assert_eq(b["inv"].size(), 10, "current size kept")
	assert_eq(b["inv"].get_stack(0).count, 12)
	assert_true(b["inv"].is_slot_empty(9))


func test_container_shrank_since_save_overflows_then_drops() -> void:
	var a := _world()
	_put(a["inv"], 4, wood, 40)   # slots: 0 wood12, 2 berry, 4 wood40 (hat moved to equipment)
	var b := _fresh_world()
	b["inv"].resize(2)
	var report: Dictionary = b["save"].from_dict(a["save"].to_dict(), db)
	# Slot 0 and 1 load in place; berry (slot 2) and wood40 (slot 4) overflow:
	# berry -> slot 1 (empty), wood40 -> merges into slot 0 up to 50 (38), 2 dropped.
	assert_eq(_ids(b["inv"]), ["wood:50", "berry:5"])
	assert_eq(report["dropped"], 2)
	assert_true(report["ok"])


func test_unknown_ids_reported_and_skipped() -> void:
	var a := _world()
	var d: Dictionary = a["save"].to_dict()
	d["containers"]["inventory"][1] = {"id": "ghost", "count": 3, "data": {}}
	d["containers"]["inventory"][3] = {"id": "ghost", "count": 1, "data": {}}
	d["containers"]["inventory"][4] = {"id": "phantom", "count": 1, "data": {}}
	var b := _fresh_world()
	var report: Dictionary = b["save"].from_dict(d, db)
	assert_true(report["ok"])
	assert_eq(report["missing_ids"], ["ghost", "phantom"])
	assert_true(b["inv"].is_slot_empty(1))
	assert_eq(b["inv"].get_stack(0).count, 12, "known items still load")


func test_unregistered_containers_ignored() -> void:
	var a := _world()
	var d: Dictionary = a["save"].to_dict()
	var b := _fresh_world()
	b["save"].unregister(&"equipment")
	var report: Dictionary = b["save"].from_dict(d, db)
	assert_eq(report["unknown_containers"], ["equipment"])
	assert_false(b["eq"].is_equipped(&"head"))
	assert_eq(b["inv"].get_stack(0).count, 12)


func test_load_replaces_existing_contents() -> void:
	var a := _world()
	var b := _fresh_world()
	_put(b["inv"], 3, wood, 7)  # stale content that must vanish
	b["save"].from_dict(a["save"].to_dict(), db)
	assert_true(b["inv"].is_slot_empty(3))


func test_wallet_without_set_gold_adjusts_by_difference() -> void:
	var a := _world()
	var b := _fresh_world()
	var duck := DuckWallet.new()
	duck.g = 1000
	b["save"].wallet = duck
	b["save"].from_dict(a["save"].to_dict(), db)
	assert_eq(duck.g, 340)


class DuckWallet extends RefCounted:
	var g: int = 0
	func get_gold() -> int:
		return g
	func try_spend(n: int) -> bool:
		if n > g:
			return false
		g -= n
		return true
	func add_gold(n: int) -> void:
		g += n


func test_null_db_fails_cleanly() -> void:
	var a := _world()
	var report: Dictionary = a["save"].from_dict(a["save"].to_dict(), null)
	assert_false(report["ok"])


# ------------------------------------------------------------------- files

func test_json_file_round_trip() -> void:
	var path := "user://__inv_test_save.json"
	var a := _world()
	assert_eq(a["save"].save_to_file(path), OK)
	assert_true(FileAccess.file_exists(path))
	var b := _fresh_world()
	var report: Dictionary = b["save"].load_from_file(path, db)
	assert_true(report["ok"])
	assert_eq(_ids(b["inv"]), _ids(a["inv"]))
	assert_eq(b["w"].get_gold(), 340)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_binary_file_round_trip_keeps_int_data() -> void:
	var path := "user://__inv_test_save.bin"
	var a := _world()
	a["inv"].get_stack(0).data["uses"] = 7  # int component data
	assert_eq(a["save"].save_to_file(path, false), OK)
	var b := _fresh_world()
	var report: Dictionary = b["save"].load_from_file(path, db, false)
	assert_true(report["ok"])
	var v: Variant = b["inv"].get_stack(0).data["uses"]
	assert_eq(typeof(v), TYPE_INT)
	assert_eq(v, 7)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_missing_file_reports_error() -> void:
	var b := _fresh_world()
	var report: Dictionary = b["save"].load_from_file("user://__does_not_exist.json", db)
	assert_false(report["ok"])
	assert_true(report.has("error"))
