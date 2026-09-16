# 09 · Theming

Everything visual comes from a `Theme`. Start from `ui/inv_default_theme.tres`: duplicate it, edit, assign to your UI root. Every entry has a code fallback, so a partial theme is fine.

## InvSlotView
| Category | Names |
|---|---|
| styles | `normal` `hover` `focus` `accept` `reject` `glow` `selected` |
| colors | `count_color` `count_shadow` `bar_bg` `bar_fg` `icon_modulate` `caption_color` `caption_shadow` |
| fonts / font_sizes | `count_font` `count_font_size` `caption_font` `caption_font_size` |
| constants | `icon_margin` `count_margin` `count_shadow_offset` `bar_height` `caption_margin` |

States: `accept`/`reject` = drop feedback while hovering with an item; `glow` = "the held item fits here"; `selected` = hotbar active slot; `focus` = gamepad.

## InvCursorView
colors `count_color` `count_shadow` · font_sizes `count_font_size` · constants `count_margin`.

## InvTooltipView
See 08.

## Sizes
`slot_size`, `columns`, `h_separation`, `v_separation` on each `InvContainerView`. Slot icons scale to fit inside `icon_margin`.

## Custom slot scene
Make a scene whose root has script `inv_slot_view.gd` (or extends it), set it as `slot_scene` on the container view. Override `_draw()` for anything the theme can't express.

## Animation
Bump on change and shake on reject use Godot 4.7 `offset_transform_*` (visual only; layout never moves). Tune in `InvSlotView.bump()` / `shake()`, or set `animate_changes = false`, `shake_on_reject = false` on the session.

## Editor preview
Set `preview_slots` on an `InvContainerView` to see placeholder slots while theming.
