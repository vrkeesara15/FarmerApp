# SeverityBadge

Pill badge for flag severity (C70).

Source: `apps/console/components/ds/SeverityBadge.tsx` (tests: `SeverityBadge.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `severity` | `'critical' | 'high' | 'medium' | 'low'` |  |

## Variants

- critical (danger + outline + '!')
- high (danger)
- medium (warning)
- low (info)

## States

- default

## Accessibility

- Text label always present; colour is supplementary
- data-severity attribute for tests/styling

## Tokens used

- `color.status.danger(+Container)`
- `color.status.warning(+Container)`
- `color.status.info(+Container)`
- `radius.pill`
- `text.console.small`
- `font.weight.semibold`
