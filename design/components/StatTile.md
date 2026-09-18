# StatTile

Compact statistic: value, label and trend arrow.

Source: `apps/console/components/ds/StatTile.tsx` (tests: `StatTile.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `value` | `string | number` |  |
| `label` | `string` |  |
| `trend` | `'up' | 'down' | 'flat'` |  |
| `trendValue` | `string` |  |
| `invertTrendColor` | `boolean` |  |
| `loading` | `boolean` |  |

## Variants

- with trend
- without trend

## States

- default
- loading (skeleton, aria-busy)

## Accessibility

- Trend colour is never the only signal: arrow icon plus sr-only text

## Tokens used

- `color.surface`
- `color.border`
- `color.success`
- `color.danger`
- `color.text.muted`
- `radius.card`
- `text.console.title`
- `text.console.small`
- `font.features (tnum)`

## Flutter

Value + label tile with optional icon and trend arrow.

Source: `apps/mobile/packages/core/lib/src/widgets/stat_tile.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `value` | `String` | pre-formatted (use formatInr / formatIndianDigits) |
| `label` | `String` |  |
| `icon` | `IconData?` |  |
| `trend` | `StatTrend?` | up | down | flat |
| `trendLabel` | `String?` | e.g. '+3' |

### Variants

- plain
- with trend

### States

- default

### Accessibility

- Trend arrow is paired with text ('Up', 'Down', 'No change').
- Display value uses tabular figures.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.surface`
- `color.border`
- `color.primary`
- `color.status.success`
- `color.status.danger`
- `color.text.secondary`
- `radius.card`
- `space.1..3`
- `text.mobile.display`
- `text.mobile.label`
- `text.mobile.caption`

### Tests

Golden: stat_tile_{light,sunlight}.png
