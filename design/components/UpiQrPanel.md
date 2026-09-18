# UpiQrPanel

Amount, QR (placeholder painter seeded from the UPI payload), countdown, and waiting / paid / failed states.

Source: `apps/mobile/packages/core/lib/src/widgets/upi_qr_panel.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `state` | `UpiPaymentState` | waiting | paid | failed |
| `amountPaise` | `int` |  |
| `qrPayload` | `String` | UPI intent; replace `UpiQrPlaceholderPainter` with a real encoder |
| `remaining` | `Duration?` | countdown in waiting state |
| `onRetry` | `VoidCallback?` | 'Show a new QR' in failed state |

## Variants

- default

## States

- waiting
- paid (overlay check)
- failed (overlay error + retry)

## Accessibility

- QR has `Semantics(image, label: 'UPI QR')`; state is icon + heading text.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.border`
- `color.text`
- `color.status.info`
- `color.status.success`
- `color.status.danger`
- `color.text.secondary`
- `radius.card`
- `radius.input`
- `space.1..4`
- `space.12`
- `text.mobile.display`
- `text.mobile.heading`
- `text.mobile.body`
- `text.mobile.label`
- `text.mobile.caption`

## Tests

Goldens: upi_qr_panel{,_paid,_failed}_{light,sunlight}.png

