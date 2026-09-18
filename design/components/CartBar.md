# CartBar

Sticky bottom bar with item count, total and a checkout AppButton; one shadow level (none in Sunlight).

Source: `apps/mobile/packages/core/lib/src/widgets/cart_bar.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `itemCount` | `int` |  |
| `totalPaise` | `int` |  |
| `onCheckout` | `VoidCallback?` | null disables |
| `actionLabel` | `String?` | default 'Checkout' |
| `estimate` | `bool` | label `cartEstimatedTotal` instead of `cartTotal` (device estimate from cached prices) |

## Variants

- default

## States

- enabled
- disabled (empty cart)

## Accessibility

- Respects the bottom safe area.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.border`
- `color.text.secondary`
- `elevation.sheet`
- `space.1`
- `space.3`
- `space.4`
- `text.mobile.heading`
- `text.mobile.caption`

## Tests

Golden: cart_bar_{light,sunlight}.png

## Usage (FA-020 / FA-021 / FA-022)

A50 (`cartViewCart` → A51) and A51 (`cartChoosePayment` → A52) with `estimate: true`; key `cart-bar`. `onCheckout: null` while a line is above what the store has (after `insufficient_stock`).
