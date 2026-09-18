# VisitCard

Visit list item: farmer, purpose (icon + label), start time, duration, VisitScoreBadge.

Source: `apps/mobile/packages/core/lib/src/widgets/visit_card.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `farmerName` | `String` |  |
| `purpose` | `VisitPurpose` | advisory | scouting | demo | collection | sale | meeting |
| `startedAtUtc` | `DateTime` | rendered in IST |
| `duration` | `Duration` |  |
| `score` | `int` | 0-100 |
| `onTap` | `VoidCallback?` |  |

## Variants

- default

## States

- verified / partial / unverified (via badge)

## Accessibility

- Meta row wraps so long localised strings never overflow.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.border`
- `color.primary`
- `color.text.secondary`
- `radius.card`
- `space.1..3`
- `text.mobile.heading`
- `text.mobile.label`
- `text.mobile.caption`

## Tests

Golden: visit_card_{light,sunlight}.png

