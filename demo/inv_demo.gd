@tool
extends Control

## Demo: player inventory + hotbar, a chest, and a filtered/partly locked
## toolbox. All item defs are built in code with generated icons so the demo
## has no asset dependencies. Copy this scene as a starting point.


class DurabilityComponent extends InvItemComponent:
	func _init() -> void:
		data_key = &"dur"
	func init_data(stack: InvItemStack) -> void:
		stack.data[data_key] = 1.0
	func can_merge(_a: InvItemStack, _b: InvItemStack) -> bool:
		return false
	func get_overlay_info(stack: InvItemStack) -> Dictionary:
		var d: float = stack.data.get(data_key, 1.0)
		return {"bar": d, "bar_color": Color(0.35, 0.85, 0.35).lerp(Color(0.9, 0.3, 0.3), 1.0 - d)}
	func get_tooltip_lines(stack: InvItemStack) -> Array:
		var d: float = stack.data.get(data_key, 1.0)
		var style := InvTooltipField.STYLE_POSITIVE if d > 0.5 else InvTooltipField.STYLE_NEGATIVE
		return [{"text": "Durability: %d%%" % int(round(d * 100.0)), "style": style}]


## Usable items (see InvUsableComponent). `user` here is the demo's player
## Dictionary; in a game it would be your player node.

class WaterComponent extends InvUsableComponent:
	@export var capacity: int = 8
	func _init() -> void:
		data_key = &"water"
		use_label = "Water"
	func init_data(stack: InvItemStack) -> void:
		stack.data[data_key] = capacity
	func can_merge(_a: InvItemStack, _b: InvItemStack) -> bool:
		return false
	func get_overlay_info(stack: InvItemStack) -> Dictionary:
		return {"bar": float(stack.data.get(data_key, 0)) / capacity, "bar_color": Color(0.35, 0.65, 1.0)}
	func get_tooltip_lines(stack: InvItemStack) -> Array:
		return ["Water: %d / %d" % [int(stack.data.get(data_key, 0)), capacity]]
	func use(stack: InvItemStack, user: Variant, _ctx: InvTransferContext) -> StringName:
		var w := int(stack.data.get(data_key, 0))
		if w <= 0:
			return FAILED
		stack.data[data_key] = w - 1
		user["watered"] += 1
		return CHANGED
	func refill(stack: InvItemStack) -> void:
		stack.data[data_key] = capacity


class FoodComponent extends InvUsableComponent:
	@export var restores: int = 25
	func _init() -> void:
		data_key = &"food"
		use_label = "Eat"
	func can_use(_stack: InvItemStack, user: Variant, _ctx: InvTransferContext) -> bool:
		return user["hunger"] < 100
	func use(_stack: InvItemStack, user: Variant, _ctx: InvTransferContext) -> StringName:
		user["hunger"] = mini(user["hunger"] + restores, 100)
		return CONSUME


class PlaceableComponent extends InvUsableComponent:
	@export var scene: PackedScene
	func _init() -> void:
		data_key = &"place"
		use_label = "Place"
	func use(_stack: InvItemStack, user: Variant, _ctx: InvTransferContext) -> StringName:
		# A real game instantiates `scene` at the cursor after checking its
		# placement rule. The demo has no world, so it just counts.
		user["placed"] += 1
		return CONSUME


class BottomRowLocked extends InvContainerPolicy:
	## Slots in the last row can't be emptied (think: bolted-in tools).
	var locked_from: int = 4
	func can_remove(_c: InvContainer, i: int, _n: int, _ctx: InvTransferContext) -> InvDropCheck:
		return InvDropCheck.reject(InvDropCheck.LOCKED) if i >= locked_from else InvDropCheck.accept()


@onready var session: InvUISession = $Session
@onready var inventory_view: InvContainerView = $Layout/Left/Inventory
@onready var hotbar_view: InvHotbarView = $Layout/Left/Hotbar
@onready var equipment_view: InvEquipmentView = $Layout/Doll/Equipment
@onready var sort_button: Button = $Layout/Left/Buttons/SortButton
@onready var compact_button: Button = $Layout/Left/Buttons/CompactButton
@onready var save_button: Button = $Layout/Left/Buttons/SaveButton
@onready var load_button: Button = $Layout/Left/Buttons/LoadButton
@onready var chest_view: InvContainerView = $Layout/Right/Chest
@onready var toolbox_view: InvContainerView = $Layout/Right/Toolbox
@onready var cursor: InvCursorView = $Cursor
@onready var tooltip: InvTooltipView = $Tooltip
@onready var shop_view: InvContainerView = $Layout/Market/Shop
@onready var counter_view: InvContainerView = $Layout/Market/Counter
@onready var bin_view: InvContainerView = $Layout/Market/Bin
@onready var gold_label: Label = $Layout/Market/GoldLabel
@onready var ship_button: Button = $Layout/Market/ShipButton
@onready var status: Label = $Status

var db := InvItemDatabase.new()
var inventory := InvContainer.new(20, &"inventory")
var hotbar := InvContainer.new(8, &"hotbar")
var chest := InvContainer.new(12, &"chest")
var toolbox := InvContainer.new(8, &"toolbox")
var equipment := InvEquipment.new([&"head", &"body", &"hand", &"feet"])
var hotbar_sel: InvHotbar
var wallet := InvWallet.new(250)
var shop := InvContainer.new(4, &"shop")
var counter := InvContainer.new(4, &"counter")
var bin := InvContainer.new(8, &"bin")
var bin_policy := InvSellBoxPolicy.new()
var save := InvSaveState.new()
var player := {"hunger": 40, "watered": 0, "placed": 0}
const SAVE_PATH := "user://inv_demo_save.json"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_items()
	_fill()

	var tool_filter := InvSlotFilter.new()
	tool_filter.required_tags = [&"tool"]
	toolbox.set_all_filters(tool_filter)
	toolbox.policy = BottomRowLocked.new()

	hotbar_sel = InvHotbar.new(hotbar)
	hotbar_sel.active_changed.connect(func(i: int, s: InvItemStack) -> void: _say("hotbar %d active: %s" % [i + 1, s]))
	equipment.equipped.connect(func(t: StringName, d: InvItemDef) -> void: _say("equipped %s in %s" % [d.id, t]))
	equipment.unequipped.connect(func(t: StringName, d: InvItemDef) -> void: _say("unequipped %s from %s" % [d.id, t]))

	shop.policy = InvShopPolicy.new()
	var counter_policy := InvSellBoxPolicy.new()
	counter_policy.payment = InvSellBoxPolicy.Payment.IMMEDIATE
	counter.policy = counter_policy
	bin_policy.payment = InvSellBoxPolicy.Payment.DEFERRED
	bin.policy = bin_policy
	shop.set_stack(0, db.make_stack(&"seed", 99))
	shop.set_stack(1, db.make_stack(&"berry", 20))
	shop.set_stack(2, db.make_stack(&"hoe"))
	shop.set_stack(3, db.make_stack(&"hat"))

	session.set_wallet(wallet)
	wallet.changed.connect(func(_g: int) -> void: _refresh_gold())
	bin.slot_changed.connect(func(_i: int) -> void: _refresh_gold())
	ship_button.pressed.connect(func() -> void: _say("shipped for %dg" % bin_policy.settle(bin, wallet, session.ctx)))
	_refresh_gold()

	inventory_view.bind(inventory)
	hotbar_view.bind_hotbar(hotbar_sel)
	chest_view.bind(chest)
	toolbox_view.bind(toolbox)
	equipment_view.bind_equipment(equipment)
	shop_view.bind(shop)
	counter_view.bind(counter)
	bin_view.bind(bin)

	session.set_cursor(cursor)
	session.set_tooltip(tooltip)
	session.register(inventory_view)
	session.register(hotbar_view)
	session.register(equipment_view)
	session.register(chest_view)
	session.register(toolbox_view)
	session.register(shop_view)
	session.register(counter_view)
	session.register(bin_view)

	save.register(&"inventory", inventory)
	save.register(&"hotbar", hotbar)
	save.register(&"equipment", equipment.container)
	save.register(&"chest", chest)
	save.register(&"toolbox", toolbox)
	save.register(&"counter", counter)
	save.register(&"bin", bin)
	save.register_hotbar(&"hotbar", hotbar_sel)
	save.wallet = wallet
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)

	sort_button.pressed.connect(func() -> void: _say("sort: %s" % InvSorter.sort(inventory, session.ctx)))
	compact_button.pressed.connect(func() -> void: _say("compact: %s" % InvSorter.compact(inventory, session.ctx)))

	session.transfer_committed.connect(func(r: InvTransferResult) -> void: _say("OK  %s" % r))
	session.transfer_rejected.connect(func(r: InvTransferResult) -> void: _say("NO  %s" % r))
	session.drop_outside_requested.connect(_on_drop_outside)
	_say("ready")
	_bake_stone_icon()


## Runtime icon baking: the stone's icon comes from a 3D model, rendered
## once at startup. Editor-side batch baking: tools/bake_icons.gd.
func _bake_stone_icon() -> void:
	var baker := InvIconBaker.new()
	baker.size = 64
	add_child(baker)
	var tex: ImageTexture = await baker.bake_scene(load("res://demo/models/stone.tscn"))
	baker.queue_free()
	if tex == null:
		return
	db.get_def(&"stone").icon = tex
	for v in session.registered_views():
		v.refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if hotbar_sel != null and not session.held.is_holding() and hotbar_sel.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == KEY_E:
			var r := hotbar_sel.use_active(player, session.ctx)
			_say("use -> %s   hunger %d · watered %d · placed %d" % [r, player["hunger"], player["watered"], player["placed"]])
			if r == InvUsableComponent.FAILED:
				hotbar_view.get_view(hotbar_sel.selected).shake()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_R:
			var s := hotbar_sel.active_stack()
			var wc: WaterComponent = (s.def.get_component(WaterComponent) as WaterComponent) if not s.is_empty() else null
			if wc != null:
				wc.refill(s)
				hotbar_sel.touch_active()
				_say("refilled")
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"ui_cancel"):
		# Closing the chest: return the held stack, then unregister externals.
		session.return_held(&"player")
		var externals: Array = [chest_view, toolbox_view, shop_view, counter_view, bin_view]
		if session.registered_views().has(chest_view):
			session.unregister_group(&"external")
			chest_view.get_parent().visible = false
			shop_view.get_parent().visible = false
			_say("externals closed (Esc again to reopen)")
		else:
			for v in externals:
				session.register(v)
			chest_view.get_parent().visible = true
			shop_view.get_parent().visible = true
			_say("externals opened")
		get_viewport().set_input_as_handled()


func _on_save() -> void:
	session.return_held(&"player")
	var err := save.save_to_file(SAVE_PATH)
	_say("saved to %s (%s)" % [ProjectSettings.globalize_path(SAVE_PATH), error_string(err)])


func _on_load() -> void:
	session.return_held(&"player")
	var report := save.load_from_file(SAVE_PATH, db)
	_say("load: %s" % str(report))
	_refresh_gold()


func _on_drop_outside(held: InvHeldStack) -> void:
	# The game owns world drops. Here we just destroy the stack.
	var s := held.take()
	_say("dropped %s into the void" % s)


func _say(t: String) -> void:
	status.text = t


func _refresh_gold() -> void:
	gold_label.text = "Gold: %d" % wallet.get_gold()
	ship_button.text = "Ship (%dg)" % bin_policy.pending_value(bin, session.ctx)


# ------------------------------------------------------------------- content

const DESCRIPTIONS := {
	&"wood": "Split logs. Burns hot, builds fences.",
	&"stone": "Field stone, good for walls.",
	&"berry": "Sweet when fresh. Sells well in town.",
	&"seed": "Plant in tilled soil and water daily.",
	&"axe": "Fells trees. Wears down with use.",
	&"hoe": "Tills soil for planting.",
	&"pick": "Breaks rock and ore.",
	&"hat": "Keeps the sun off.",
	&"coat": "A long oilskin duster.",
	&"boots": "Sturdy leather work boots.",
	&"can": "Holds 8 waterings. R refills it.",
	&"fence": "Placeable. E to place the selected one.",
}


func _build_items() -> void:
	_def(&"wood", "Wood", 50, Color(0.62, 0.42, 0.22), [&"material", &"sellable"])
	_def(&"stone", "Stone", 50, Color(0.55, 0.55, 0.58), [&"material"])
	_def(&"berry", "Berry", 20, Color(0.75, 0.2, 0.35), [&"food", &"sellable"], &"", [FoodComponent.new()])
	_def(&"can", "Watering Can", 1, Color(0.4, 0.6, 0.9), [&"tool"], &"hand", [WaterComponent.new()])
	var fence := PlaceableComponent.new()
	fence.scene = load("res://demo/models/stone.tscn")
	_def(&"fence", "Fence Post", 20, Color(0.8, 0.7, 0.5), [&"placeable"], &"", [fence])
	_def(&"seed", "Seed", 99, Color(0.85, 0.75, 0.3), [&"seed"])
	_def(&"axe", "Axe", 1, Color(0.3, 0.6, 0.85), [&"tool"], &"hand", [DurabilityComponent.new()])
	_def(&"hoe", "Hoe", 1, Color(0.35, 0.75, 0.55), [&"tool"], &"hand", [DurabilityComponent.new()])
	_def(&"pick", "Pickaxe", 1, Color(0.7, 0.5, 0.85), [&"tool"], &"hand", [DurabilityComponent.new()])
	_def(&"hat", "Straw Hat", 1, Color(0.9, 0.8, 0.45), [&"armor"], &"head")
	_def(&"coat", "Duster", 1, Color(0.5, 0.35, 0.25), [&"armor"], &"body")
	_def(&"boots", "Boots", 1, Color(0.35, 0.25, 0.2), [&"armor"], &"feet")
	_price(&"wood", 0, 2)
	_price(&"stone", 0, 1)
	_price(&"berry", 8, 3)
	_price(&"seed", 10, 2)
	_price(&"axe", 150, 50)
	_price(&"hoe", 120, 40)
	_price(&"pick", 200, 70)
	_price(&"hat", 60, 20)
	_price(&"coat", 90, 30)
	_price(&"boots", 45, 15)
	_price(&"can", 80, 25)
	_price(&"fence", 5, 1)


func _price(id: StringName, buy: int, sell: int) -> void:
	var d := db.get_def(id)
	d.price = buy
	d.sell_price = sell


func _def(id: StringName, label: String, max_stack: int, color: Color, tags: Array, equip: StringName = &"", comps: Array = []) -> void:
	var d := InvItemDef.new()
	d.id = id
	d.display_name = label
	d.description = DESCRIPTIONS.get(id, "")
	d.max_stack = max_stack
	d.icon = _icon(color)
	var t: Array[StringName] = []
	for x in tags:
		t.append(x)
	d.tags = t
	d.equip_type = equip
	var c: Array[InvItemComponent] = []
	for x in comps:
		c.append(x)
	d.components = c
	db.register(d)


func _fill() -> void:
	inventory.set_stack(0, db.make_stack(&"wood", 32))
	inventory.set_stack(1, db.make_stack(&"wood", 50))
	inventory.set_stack(2, db.make_stack(&"stone", 12))
	inventory.set_stack(5, db.make_stack(&"berry", 7))
	inventory.set_stack(6, db.make_stack(&"seed", 99))
	var axe := db.make_stack(&"axe")
	axe.data[&"dur"] = 0.35
	inventory.set_stack(9, axe)
	hotbar.set_stack(0, db.make_stack(&"hoe"))
	hotbar.set_stack(1, db.make_stack(&"wood", 5))
	hotbar.set_stack(2, db.make_stack(&"can"))
	hotbar.set_stack(3, db.make_stack(&"berry", 4))
	hotbar.set_stack(4, db.make_stack(&"fence", 12))
	chest.set_stack(0, db.make_stack(&"wood", 40))
	chest.set_stack(1, db.make_stack(&"berry", 18))
	chest.set_stack(7, db.make_stack(&"stone", 50))
	toolbox.set_stack(4, db.make_stack(&"pick"))
	inventory.set_stack(14, db.make_stack(&"hat"))
	inventory.set_stack(15, db.make_stack(&"boots"))
	chest.set_stack(5, db.make_stack(&"coat"))


static func _icon(color: Color, px: int = 32) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var inset := 4
	img.fill_rect(Rect2i(inset, inset, px - inset * 2, px - inset * 2), color.darkened(0.35))
	img.fill_rect(Rect2i(inset + 2, inset + 2, px - inset * 2 - 4, px - inset * 2 - 4), color)
	img.fill_rect(Rect2i(inset + 4, inset + 4, 6, 4), color.lightened(0.35))
	return ImageTexture.create_from_image(img)
