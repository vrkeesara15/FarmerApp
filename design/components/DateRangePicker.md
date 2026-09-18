# DateRangePicker

Two native date inputs (start/end) with validation. ISO YYYY-MM-DD values; API interprets as IST days.

Source: `apps/console/components/ds/DateRangePicker.tsx` (tests: `DateRangePicker.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `value` | `{start, end}` |  |
| `onChange` | `(range) => void` |  |
| `label` | `string` | sr-only legend |
| `min / max` | `string` |  |
| `disabled` | `boolean` |  |

## Variants

- inline

## States

- default
- invalid (end before start: danger border + alert)
- disabled

## Accessibility

- <fieldset>/<legend>
- inputs labelled 'Start date'/'End date'
- aria-invalid on both inputs when the range is invalid

## Tokens used

- `color.border`
- `color.surface`
- `color.danger`
- `radius.input`
- `font.features (tnum)`
