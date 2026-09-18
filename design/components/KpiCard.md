# KpiCard

Console KPI card with headline value, target progress, trend and optional chart slot (C10).

Source: `apps/console/components/ds/KpiCard.tsx` (tests: `KpiCard.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `title` | `string` |  |
| `value` | `string` | pre-formatted via lib/format |
| `target` | `string` | formatted target |
| `progress` | `number` | 0..1 toward target |
| `trend` | `'up' | 'down' | 'flat'` |  |
| `trendValue` | `string` | e.g. +8% |
| `invertTrendColor` | `boolean` | up is bad (overdue credit) |
| `chart` | `ReactNode` | sparkline slot |
| `footer` | `ReactNode` |  |
| `loading` | `boolean` |  |
| `error` | `string` |  |
| `onClick` | `() => void` | renders as <button> |

## Variants

- static card
- clickable (button)
- with target progress
- with chart slot

## States

- default
- loading (skeletons, aria-busy)
- error (danger border + alert)
- hover when clickable

## Accessibility

- Progress bar exposes role=progressbar with aria-valuenow
- Trend arrow has sr-only text ('Up 8% vs previous period')
- Clickable cards are real buttons

## Tokens used

- `color.surface`
- `color.border`
- `color.primary`
- `color.success`
- `color.danger`
- `color.text.secondary`
- `color.text.muted`
- `radius.card`
- `text.console.display`
- `text.console.small`
- `font.features (tnum)`
