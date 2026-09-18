# Dialog

Modal dialog with title, description, body, cancel/confirm footer and error line.

Source: `apps/console/components/ds/Dialog.tsx` (tests: `Dialog.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `open / onOpenChange` | `` |  |
| `title` | `string` | required |
| `description` | `string` |  |
| `children` | `ReactNode` |  |
| `trigger` | `ReactNode` | optional asChild trigger |
| `confirmLabel / cancelLabel` | `string` |  |
| `onConfirm` | `() => void` |  |
| `destructive` | `boolean` |  |
| `loading` | `boolean` | locks close and actions |
| `error` | `string` |  |

## Variants

- confirm
- destructive confirm
- information (no confirm)

## States

- closed
- open
- loading
- error

## Accessibility

- Radix Dialog: focus trap, Escape closes, aria-labelledby/aria-describedby
- Close icon has sr-only 'Close dialog'
- Cannot be dismissed while loading

## Tokens used

- `color.surface`
- `color.border`
- `color.text`
- `radius.sheet`
- `elevation.sheet`
- `text.console.heading`
- `text.console.body`
