# SegmentedControl

Single-choice segmented control (radiogroup) for views like Day/Week/Month.

Source: `apps/console/components/ds/SegmentedControl.tsx` (tests: `SegmentedControl.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `options` | `{value, label, icon?, disabled?}[]` |  |
| `value` | `V` |  |
| `onChange` | `(v) => void` |  |
| `label` | `string` | aria-label |
| `size` | `'sm' | 'md'` |  |
| `disabled` | `boolean` |  |

## Variants

- md
- sm

## States

- default
- selected
- disabled option
- disabled group

## Accessibility

- role=radiogroup / role=radio with aria-checked
- Roving tabindex; Left/Right arrows move selection

## Tokens used

- `color.background`
- `color.surface`
- `color.border`
- `color.text`
- `color.text.secondary`
- `radius.input`
- `text.console.body`
- `text.console.small`
