# 08 · Tooltips

## Turn on
In your inventory UI scene: add a `PanelContainer` node, attach `addons/slot_inventory/ui/inv_tooltip_view.gd`, name it `Tooltip`. In the scene's `_ready()`: `$Session.set_tooltip($Tooltip)`.

On the `Session` node (Inspector): **Tooltip Delay** (0.35 s; 0 = instant), **Tooltip While Holding** (off by default).

## Choose what shows (no code)
1. New Resource → `InvTooltipProvider` → save `ui/tooltip.tres`.
2. In **Fields**, add `InvTooltipField` entries. Each: **Kind** (Name, Description, Count, Max Stack, Tags, Equip Type, Price, Sell Price, Id, Components, Policy, Separator), **Label** prefix, **Format** (`%d gold`), **Style** (title / body / muted / accent / positive / negative), **Hide If Empty**, **Only With Policy** (`InvShopPolicy` → line appears only in shops).
3. Reorder to taste. Drag the resource onto the tooltip view's **Provider**.

Different screens can use different providers. No provider = sensible default.

`Components` pulls each component's `get_tooltip_lines()` (durability, water). `Policy` pulls the container's `slot_tooltip_lines()` (buy/sell prices).

## Your own line
```gdscript
class_name QualityField extends InvTooltipField
func _init(): kind = Kind.CUSTOM
func lines(stack, _c, _i, _ctx) -> Array[Dictionary]:
    return [{"text": "Quality: " + "★".repeat(stack.data.get("q", 1)), "style": STYLE_ACCENT}]
```
Add it to the provider's Fields like any other.

## Look
Theme type `InvTooltipView`: `panel` stylebox, `title_color body_color muted_color accent_color positive_color negative_color`, `title_font_size body_font_size muted_font_size`, constants `max_width`, `slot_gap`.
