# FarmerCard

Farmer list item: photo or initials, name, village, up to two CropChips, last visit, balance-due badge; FA-012 adds the offline `pendingSync` note and the `attention` badge for a farmer the server rejected.

Source: `apps/mobile/packages/core/lib/src/widgets/farmer_card.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `name / village` | `String` | required |
| `photo` | `ImageProvider?` | initials when null |
| `crops` | `List<CropChipData>` | first two shown |
| `lastVisitUtc` | `DateTime?` | rendered DD-MM-YYYY in IST |
| `balanceDuePaise` | `int` | badge hidden when 0 |
| `pendingSync` | `bool` | cloud icon + `farmerPendingSync` on the footer row (queued op not yet on the server) |
| `attention` | `bool` | danger row (error icon + `farmerRejected`) under the footer (A64 / A22 explain) |
| `onTap` | `VoidCallback?` |  |

## Variants

- with photo
- initials

## States

- default
- with due badge
- no visit yet
- pending sync
- needs attention

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
- `color.status.danger`
- `color.status.dangerContainer`
- `color.status.info`
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

