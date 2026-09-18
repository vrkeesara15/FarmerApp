# SearchBar

Search input with icon and clear button.

Source: `apps/console/components/ds/SearchBar.tsx` (tests: `SearchBar.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `value / onChange` | `` |  |
| `onSubmit` | `(v) => void` | Enter |
| `placeholder` | `string` | default 'Search' |
| `label` | `string` | aria-label, default 'Search' |
| `loading` | `boolean` | icon pulses |
| `disabled` | `boolean` |  |

## Variants

- default

## States

- default
- with value (clear button)
- loading
- disabled

## Accessibility

- role=search container, type=search input
- Clear button labelled 'Clear search'

## Tokens used

- `color.surface`
- `color.border`
- `color.text`
- `color.text.muted`
- `color.primary`
- `radius.input`
- `text.console.body`
