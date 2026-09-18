# PaymentMethodSelector

Large radio list: UPI QR, payment link, cash, credit; each with icon, title and hint.

Source: `apps/mobile/packages/core/lib/src/widgets/payment_method_selector.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `selected` | `PaymentMethod?` |  |
| `onChanged` | `ValueChanged<PaymentMethod>?` | null disables all |
| `available` | `Set<PaymentMethod>` | others render disabled |
| `creditHint` | `String?` | e.g. limit remaining |

## Variants

- default

## States

- selected
- unselected
- disabled

## Accessibility

- `Semantics(inMutuallyExclusiveGroup, checked, enabled, label)`; rows are >= 56 dp.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.primary`
- `color.primary.container`
- `color.border`
- `color.text`
- `color.text.secondary`
- `color.text.muted`
- `radius.card`
- `size.primaryButtonHeight`
- `space.2`
- `space.3`
- `text.mobile.body`
- `text.mobile.caption`

## Tests

Golden: payment_method_selector_{light,sunlight}.png

