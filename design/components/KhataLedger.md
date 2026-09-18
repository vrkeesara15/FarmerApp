# KhataLedger

Balance header (colour by overdue), due date, primary action, and debit/credit entries.

Source: `apps/mobile/packages/core/lib/src/widgets/khata_ledger.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `balancePaise` | `int` |  |
| `dueDateUtc` | `DateTime?` | overdue => danger |
| `entries` | `List<KhataEntry>` | dateUtc, description, amountPaise, isCredit |
| `actionLabel` | `String?` | 'Pay now' (farmer) / 'Collect' (agent) |
| `onAction` | `VoidCallback?` | button hidden when null |

## Variants

- farmer (Pay now)
- agent (Collect)

## States

- no entries
- due
- overdue
- settled

## Accessibility

- Debit/credit conveyed by arrow icon + 'Debit'/'Credit' text and sign.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.background`
- `color.border`
- `color.status.success`
- `color.status.warning`
- `color.status.danger`
- `color.text`
- `color.text.secondary`
- `radius.card`
- `space.1..4`
- `text.mobile.display`
- `text.mobile.heading`
- `text.mobile.body`
- `text.mobile.label`
- `text.mobile.caption`

## Tests

Golden: khata_ledger_{light,sunlight}.png

