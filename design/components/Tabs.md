# Tabs

Underline tabs with optional count badges and lazy content.

Source: `apps/console/components/ds/Tabs.tsx` (tests: `Tabs.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `items` | `TabItem[]` | value, label, count?, disabled?, content? |
| `value / defaultValue` | `` |  |
| `onValueChange` | `(v) => void` |  |
| `label` | `string` | aria-label for the tablist |

## Variants

- with counts
- with disabled tab

## States

- default
- active (primary underline, semibold)
- disabled

## Accessibility

- Radix Tabs: roving tabindex, arrow keys
- tablist labelled via `label`

## Tokens used

- `color.border`
- `color.primary`
- `color.text`
- `color.text.secondary`
- `color.background`
- `radius.pill`
- `text.console.body`
- `text.console.small`
