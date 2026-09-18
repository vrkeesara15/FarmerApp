# Toasts

Sonner-based toast host (mount once in root layout) plus a typed `toast` helper.

Source: `apps/console/components/ds/Toasts.tsx` (tests: `Toasts.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `toast.success/error/info/warning` | `(message, description?)` |  |
| `toast.fromError` | `(err: unknown)` | ApiError -> problem title/detail; other -> generic |
| `toast.dismiss` | `` |  |

## Variants

- success
- error
- warning
- info

## States

- default
- with description
- with close button

## Accessibility

- Sonner announces toasts via aria-live
- Colour is via border only; title text carries the meaning

## Tokens used

- `color.surface`
- `color.text`
- `color.border`
- `color.success`
- `color.danger`
- `color.warning`
- `color.info`
- `radius.card`
- `elevation.sheet`
