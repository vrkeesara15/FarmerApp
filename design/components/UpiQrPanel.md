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
| `statusText` | `String?` | overrides the state heading (e.g. `upiExpired`) |

## Variants

- default

## States

- waiting
- paid (overlay check)
- failed (overlay error + retry)
- expired (failed state with `upiExpired`)

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

## Usage (FA-020 / FA-021 / FA-022)

The QR is rendered from the provider's `qr_payload` with `qr_flutter`, always black on white so scanners read it in Sunlight too; an empty payload falls back to the placeholder painter (previews). A53 drives `state` from `UpiPoller` (3 s, backing off to 10 s, stop at expiry) and `remaining` from `expires_at` − now.
