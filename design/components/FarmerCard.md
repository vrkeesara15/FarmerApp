# FarmerCard

Farmer list item: photo or initials, name, village, up to two CropChips, last visit, balance-due badge.

Source: `apps/mobile/packages/core/lib/src/widgets/farmer_card.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `name / village` | `String` | required |
| `photo` | `ImageProvider?` | initials when null |
| `crops` | `List<CropChipData>` | first two shown |
| `lastVisitUtc` | `DateTime?` | rendered DD-MM-YYYY in IST |
| `balanceDuePaise` | `int` | badge hidden when 0 |
| `onTap` | `VoidCallback?` |  |

## Variants

- with photo
- initials

## States

- default
- with due badge
- no visit yet

## Accessibility

- `Semantics(button, label: '<name>, <village>')`.
- Due badge uses rupee icon + text.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.border`
- `color.primary`
- `color.primary.container`
- `color.status.warning`
- `color.status.warningContainer`
- `color.text.secondary`
- `radius.card`
- `radius.pill`
- `space.1..3`
- `space.6`
- `text.mobile.heading`
- `text.mobile.body`
- `text.mobile.caption`

## Tests

Golden: farmer_card_{light,sunlight}.png

