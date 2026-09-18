# FilterBar

Standard filters for every data view: cluster, store, officer, crop, date range; clear and export.

Source: `apps/console/components/ds/FilterBar.tsx` (tests: `FilterBar.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `value` | `FilterValues` | {cluster?, store?, officer?, crop?, date?} |
| `onChange` | `(next) => void` |  |
| `options` | `{clusters?, stores?, officers?, crops?}` | FilterOption[] each |
| `show` | `Partial<Record<filter, boolean>>` | hide filters a screen does not need |
| `onExport` | `() => void` | shows Export button |
| `exporting` | `boolean` |  |
| `disabled` | `boolean` |  |

## Variants

- all filters
- subset via show
- with export

## States

- default
- active (Clear button)
- disabled
- exporting

## Accessibility

- role=group labelled 'Filters'
- Native <select> and <input type=date> for keyboard and AT support

## Tokens used

- `color.surface`
- `color.border`
- `radius.card`
- `radius.input`
- `text.console.small`

## Notes

Selects are native for now; swap to a shadcn Select when multi-select is needed.
