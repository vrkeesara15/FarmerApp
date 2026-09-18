# FlagCard

Validation flag summary for the C70 inbox: severity, rule, officer, SLA and actions.

Source: `apps/console/components/ds/FlagCard.tsx` (tests: `FlagCard.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `id` | `string` |  |
| `title` | `string` |  |
| `severity` | `Severity` |  |
| `rule` | `string` | rule id e.g. VV-003 |
| `officerName` | `string` |  |
| `summary` | `string` |  |
| `raisedAt` | `Date | string` | rendered DD-MM-YYYY HH:mm IST |
| `slaMinutesLeft` | `number` | negative = breached |
| `onOpen` | `(id) => void` |  |
| `onAssign` | `(id) => void` |  |
| `loading` | `boolean` |  |

## Variants

- left border colour by severity
- with/without SLA
- with/without actions

## States

- default
- SLA due
- SLA breached (danger)
- loading (skeleton, aria-busy)

## Accessibility

- <article> with h3 title
- <time dateTime> for raisedAt
- Action buttons are AppButtons with text labels

## Tokens used

- `color.surface`
- `color.border`
- `color.danger`
- `color.warning`
- `color.info`
- `radius.card`
- `text.console.heading`
- `text.console.small`
