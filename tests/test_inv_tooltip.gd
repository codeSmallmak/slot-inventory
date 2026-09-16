@tool
extends McpTestSuite

## Tooltip tests: InvTooltipField kinds and options, InvTooltipProvider
## composition, component/policy hooks, custom fields, and the session's
## hover-delay behaviour driving an InvTooltipView (off-tree).


class DurabilityComponent extends InvItemComponent:
	func _init() -> void:
		data_key = &"dur"
	func init_data(stack: InvItemStack) -> void:
		stack.data[data_key] = 0.4
	func get_tooltip_lines(stack: InvItemStack) -> Array:
		return [{"text": "Durability: %d%%" % int(stack.data[data_key] * 100), "style": InvTooltipField.STYLE_NEGATIVE}]


class QualityField extends InvTooltipField:
	func _init() -> void:
		kind = Kind.CUSTOM
	func lines(stack: InvItemStack, _c: InvContainer, _i: int, _ctx: InvTransferContext) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		if stack != null and not stack.is_empty():
			out.append({"text": "Quality: " + "*".repeat(int(stack.data.get("q", 1))), "style": STYLE_ACCENT})
		return out


var db: InvItemDatabase
var wood: InvItemDef
var axe: InvItemDef
var seed: InvItemDef


func suite_name() -> String:
	return "inv_tooltip"


func suite_setup(_ctx: Dictionary) -> void:
	db = InvItemDatabase.new()
	wood = _def(&"wood", "Wood", "Split logs.", 50, [&"material", &"sellable"], 0, 2)
	axe = _def(&"axe", "Axe", "", 1, [&"tool"], 150, 50, &"hand", [DurabilityComponent.new()])
	seed = _def(&"seed", "", "", 99, [], 10, 0)


func _def(id: StringName, label: String, desc: String, max_stack: int, tags: Array, price: int, sell: int, equip: StringName = &"", comps: Array = []) -> InvItemDef:
	var d := InvItemDef.new()
	d.id = id
	d.display_name = label
	d.description = desc
	d.max_stack = max_stack
	var t: Array[StringName] = []
	for x in tags:
		t.append(x)
	d.tags = t
	d.price = price
	d.sell_price = sell
	d.equip_type = equip
	var c: Array[InvItemComponent] = []
	for x in comps:
		c.append(x)
	d.components = c
	db.register(d)
	return d


func _texts(lines: Array[Dictionary]) -> Array:
	var out := []
	for l in lines:
		out.append(l["text"])
	return out


func _styles(lines: Array[Dictionary]) -> Array:
	var out := []
	for l in lines:
		out.append(l["style"])
	return out


# ------------------------------------------------------------------ fields

func test_basic_kinds() -> void:
	var s := InvItemStack.make(wood, 12)
	assert_eq(_texts(InvTooltipField.make(InvTooltipField.Kind.NAME).lines(s, null, -1, null)), ["Wood"])
	assert_eq(_texts(InvTooltipField.make(InvTooltipField.Kind.DESCRIPTION).lines(s, null, -1, null)), ["Split logs."])
	assert_eq(_texts(InvTooltipField.make(InvTooltipField.Kind.COUNT).lines(s, null, -1, null)), ["x12"])
	assert_eq(_texts(InvTooltipField.make(InvTooltipField.Kind.MAX_STACK).lines(s, null, -1, null)), ["12 / 50"])
	assert_eq(_texts(InvTooltipField.make(InvTooltipField.Kind.TAGS).lines(s, null, -1, null)), ["material, sellable"])
	assert_eq(_texts(InvTooltipField.make(InvTooltipField.Kind.SELL_PRICE).lines(s, null, -1, null)), ["2g"])
	assert_eq(_texts(InvTooltipField.make(InvTooltipField.Kind.ID).lines(s, null, -1, null)), ["wood"])


func test_name_falls_back_to_id_and_empties_hide() -> void:
	var s := InvItemStack.make(seed, 3)
	assert_eq(_texts(InvTooltipField.make(InvTooltipField.Kind.NAME).lines(s, null, -1, null)), ["seed"])
	assert_eq(InvTooltipField.make(InvTooltipField.Kind.DESCRIPTION).lines(s, null, -1, null).size(), 0, "empty description hidden")
	assert_eq(InvTooltipField.make(InvTooltipField.Kind.SELL_PRICE).lines(s, null, -1, null).size(), 0, "zero price hidden")
	assert_eq(InvTooltipField.make(InvTooltipField.Kind.TAGS).lines(s, null, -1, null).size(), 0)
	var show_zero := InvTooltipField.make(InvTooltipField.Kind.SELL_PRICE)
	show_zero.hide_if_empty = false
	assert_eq(_texts(show_zero.lines(s, null, -1, null)), ["0g"])
	assert_eq(InvTooltipField.make(InvTooltipField.Kind.NAME).lines(InvItemStack.new(), null, -1, null).size(), 0, "empty stack: nothing")


func test_label_format_and_style() -> void:
	var s := InvItemStack.make(wood, 5)
	var f := InvTooltipField.make(InvTooltipField.Kind.PRICE, InvTooltipField.STYLE_ACCENT, "Buy: ", "%d gold")
	f.hide_if_empty = false
	var l := f.lines(s, null, -1, null)
	assert_eq(_texts(l), ["Buy: 0 gold"])
	assert_eq(_styles(l), [InvTooltipField.STYLE_ACCENT])
	var c := InvTooltipField.make(InvTooltipField.Kind.COUNT, InvTooltipField.STYLE_BODY, "Count ", "%d pcs")
	assert_eq(_texts(c.lines(s, null, -1, null)), ["Count 5 pcs"])


func test_component_and_custom_fields() -> void:
	var s := InvItemStack.make(axe, 1)
	var l := InvTooltipField.make(InvTooltipField.Kind.COMPONENTS).lines(s, null, -1, null)
	assert_eq(_texts(l), ["Durability: 40%"])
	assert_eq(_styles(l), [InvTooltipField.STYLE_NEGATIVE], "hook's own style wins")
	var w := InvItemStack.make(wood, 1)
	w.data["q"] = 3
	assert_eq(_texts(QualityField.new().lines(w, null, -1, null)), ["Quality: ***"])


func test_policy_field_and_only_with_policy_gate() -> void:
	var shop := InvContainer.new(1, &"shop")
	shop.policy = InvShopPolicy.new()
	shop.set_stack(0, InvItemStack.make(seed, 99))
	var ctx := InvTransferContext.make(InvWallet.new(5))
	var pol := InvTooltipField.make(InvTooltipField.Kind.POLICY)
	var l := pol.lines(shop.get_stack(0), shop, 0, ctx)
	assert_eq(_texts(l), ["Buy: 10g"])
	assert_eq(_styles(l), [InvTooltipField.STYLE_NEGATIVE], "can't afford -> negative")
	ctx.wallet.add_gold(100)
	assert_eq(_styles(pol.lines(shop.get_stack(0), shop, 0, ctx)), [InvTooltipField.STYLE_ACCENT])
	# Gate a field on the policy class.
	var gated := InvTooltipField.make(InvTooltipField.Kind.NAME)
	gated.only_with_policy = "InvShopPolicy"
	assert_eq(gated.lines(shop.get_stack(0), shop, 0, ctx).size(), 1)
	var plain := InvContainer.new(1)
	plain.set_stack(0, InvItemStack.make(seed, 1))
	assert_eq(gated.lines(plain.get_stack(0), plain, 0, ctx).size(), 0)
	gated.only_with_policy = "InvContainerPolicy"
	assert_eq(gated.lines(shop.get_stack(0), shop, 0, ctx).size(), 1, "base class matches subclasses")


func test_sell_box_policy_lines() -> void:
	var box := InvContainer.new(1)
	var p := InvSellBoxPolicy.new()
	p.payment = InvSellBoxPolicy.Payment.DEFERRED
	box.policy = p
	box.set_stack(0, InvItemStack.make(wood, 10))
	var l := InvTooltipField.make(InvTooltipField.Kind.POLICY).lines(box.get_stack(0), box, 0, null)
	assert_eq(_texts(l), ["Ships for 2g (x10 = 20g)", "Take back: free"])
	p.payment = InvSellBoxPolicy.Payment.IMMEDIATE
	p.buyback = false
	l = InvTooltipField.make(InvTooltipField.Kind.POLICY).lines(box.get_stack(0), box, 0, null)
	assert_eq(_texts(l), ["Sold for 2g each", "No returns"])


# ---------------------------------------------------------------- provider

func test_default_provider_composition() -> void:
	var p := InvTooltipProvider.default_provider()
	var s := InvItemStack.make(axe, 1)
	var l := p.build(s)
	assert_eq(_texts(l), ["Axe", "Durability: 40%", "", "tool"])
	assert_eq(_styles(l)[0], InvTooltipField.STYLE_TITLE)
	assert_eq(_styles(l)[3], InvTooltipField.STYLE_MUTED)


func test_provider_collapses_separators_and_is_reorderable() -> void:
	var p := InvTooltipProvider.new()
	p.fields = [
		InvTooltipField.make(InvTooltipField.Kind.SEPARATOR),
		InvTooltipField.make(InvTooltipField.Kind.TAGS),
		InvTooltipField.make(InvTooltipField.Kind.SEPARATOR),
		InvTooltipField.make(InvTooltipField.Kind.SEPARATOR),
		InvTooltipField.make(InvTooltipField.Kind.DESCRIPTION),
		InvTooltipField.make(InvTooltipField.Kind.NAME),
		InvTooltipField.make(InvTooltipField.Kind.SEPARATOR),
	]
	var s := InvItemStack.make(wood, 1)
	assert_eq(_texts(p.build(s)), ["material, sellable", "", "Split logs.", "Wood"])
	p.collapse_separators = false
	assert_eq(p.build(s).size(), 7)
	p.collapse_separators = true
	assert_eq(p.build_text(InvItemStack.make(seed, 1)), "seed", "no tags/description; name falls back to id")


func test_provider_empty_stack_yields_nothing() -> void:
	var p := InvTooltipProvider.default_provider()
	assert_eq(p.build(InvItemStack.new()).size(), 0)
	assert_eq(p.build(null).size(), 0)


# --------------------------------------------------------------------- view

func _tip() -> InvTooltipView:
	var t := InvTooltipView.new()
	track(t)
	return t


func _session() -> InvUISession:
	var s := InvUISession.new()
	s.shake_on_reject = false
	track(s)
	return s


func _view(c: InvContainer, group: StringName = &"player") -> InvContainerView:
	var v := InvContainerView.new()
	v.group = group
	v.bind(c)
	for i in v.slot_count():
		var sv := v.get_view(i)
		sv.animate_changes = false
		sv.size = Vector2(48, 48)
		sv.position = Vector2(i * 50, 0)
	track(v)
	return v


func test_view_show_hide_and_bbcode() -> void:
	var t := _tip()
	var inv := InvContainer.new(2)
	inv.set_stack(0, InvItemStack.make(wood, 7))
	var iv := _view(inv)
	t.show_for(iv.get_view(0))
	assert_true(t.visible)
	assert_true(t.is_showing_for(iv.get_view(0)))
	var bb := t.to_bbcode(InvTooltipProvider.default_provider().build(inv.get_stack(0)))
	assert_contains(bb, "Wood")
	assert_contains(bb, "[color=#")
	assert_contains(bb, "[font_size=")
	t.show_for(iv.get_view(1))
	assert_false(t.visible, "empty slot: nothing to show")
	t.show_for(iv.get_view(0))
	t.hide_tip()
	assert_false(t.visible)


func test_view_escapes_brackets_and_refreshes_on_slot_change() -> void:
	var t := _tip()
	var spiky := _def(&"spiky", "A [b]bold[/b] name", "", 1, [], 0, 0)
	var inv := InvContainer.new(1)
	inv.set_stack(0, InvItemStack.make(spiky, 1))
	var iv := _view(inv)
	t.show_for(iv.get_view(0))
	assert_contains(t.to_bbcode(InvTooltipProvider.default_provider().build(inv.get_stack(0))), "[lb]b]bold[lb]/b]")
	inv.set_stack(0, InvItemStack.make(wood, 3))
	assert_true(t.visible, "still showing after content change")
	inv.clear_slot(0)
	assert_false(t.visible, "slot emptied -> tooltip gone")


func test_session_delay_and_hide_while_holding() -> void:
	var s := _session()
	var t := _tip()
	s.set_tooltip(t)
	s.tooltip_delay = 0.3
	var inv := InvContainer.new(2)
	inv.set_stack(0, InvItemStack.make(wood, 7))
	inv.set_stack(1, InvItemStack.make(axe, 1))
	var iv := _view(inv)
	s.register(iv)
	var v0 := iv.get_view(0)
	var v1 := iv.get_view(1)
	v0._notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_false(t.visible, "not before the delay")
	s.tick_tooltip(0.2)
	assert_false(t.visible)
	s.tick_tooltip(0.2)
	assert_true(t.is_showing_for(v0))
	# Move to another slot: hides immediately, reappears after the delay.
	v0._notification(Control.NOTIFICATION_MOUSE_EXIT)
	v1._notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_false(t.visible)
	s.tick_tooltip(0.3)
	assert_true(t.is_showing_for(v1))
	# Leaving hides.
	v1._notification(Control.NOTIFICATION_MOUSE_EXIT)
	assert_false(t.visible)
	# Hovering while holding an item shows nothing (default).
	v0._notification(Control.NOTIFICATION_MOUSE_ENTER)
	s.tick_tooltip(1.0)
	assert_true(t.is_showing_for(v0))
	s.primary(v0)  # pick up -> held changed -> tooltip hidden
	assert_true(s.held.is_holding())
	assert_false(t.visible)
	s.tick_tooltip(1.0)
	assert_false(t.visible, "no pending tooltip while holding")
	s.tooltip_while_holding = true
	v0._notification(Control.NOTIFICATION_MOUSE_EXIT)
	v1._notification(Control.NOTIFICATION_MOUSE_ENTER)
	s.tick_tooltip(1.0)
	assert_true(t.is_showing_for(v1), "allowed when tooltip_while_holding")


func test_session_zero_delay_and_leave_before_delay() -> void:
	var s := _session()
	var t := _tip()
	s.set_tooltip(t)
	s.tooltip_delay = 0.0
	var inv := InvContainer.new(1)
	inv.set_stack(0, InvItemStack.make(wood, 1))
	var iv := _view(inv)
	s.register(iv)
	var v0 := iv.get_view(0)
	v0._notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_true(t.is_showing_for(v0), "immediate")
	v0._notification(Control.NOTIFICATION_MOUSE_EXIT)
	s.tooltip_delay = 0.5
	v0._notification(Control.NOTIFICATION_MOUSE_ENTER)
	v0._notification(Control.NOTIFICATION_MOUSE_EXIT)
	s.tick_tooltip(1.0)
	assert_false(t.visible, "left before the delay elapsed")


func test_session_custom_provider_on_view() -> void:
	var s := _session()
	var t := _tip()
	var p := InvTooltipProvider.new()
	p.fields = [InvTooltipField.make(InvTooltipField.Kind.ID, InvTooltipField.STYLE_TITLE, "#")]
	t.provider = p
	s.set_tooltip(t)
	s.tooltip_delay = 0.0
	var inv := InvContainer.new(1)
	inv.set_stack(0, InvItemStack.make(wood, 1))
	var iv := _view(inv)
	s.register(iv)
	iv.get_view(0)._notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_true(t.visible)
	assert_eq(p.build_text(inv.get_stack(0)), "#wood")
