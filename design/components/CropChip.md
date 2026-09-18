# CropChip

Crop icon + name (+ stage) chip; optionally selectable.

Source: `apps/mobile/packages/core/lib/src/widgets/crop_chip.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `data` | `CropChipData` | name, stage?, icon (default leaf) |
| `selected` | `bool` |  |
| `onTap` | `VoidCallback?` | makes it a toggle |

## Variants

- display
- selectable

## States

- default
- selected

## Accessibility

- `Semantics(button?, selected, label)`; min height 40 dp inside 48 dp rows.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.primary`
- `color.primary.container`
- `color.border`
- `color.text.secondary`
- `radius.chip`
- `size.icon`
- `space.1..3`
- `text.mobile.label`
- `text.mobile.caption`

## Tests

Golden: crop_chip_{light,sunlight}.png

