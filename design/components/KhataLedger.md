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
| `now` | `DateTime?` | clock for the overdue colour (tests / goldens) |
| `header` | `Widget?` | extra content under the balance (A58 overdue bucket pills) |
| `KhataEntry.dueDateUtc / harvestMonthUtc` | `DateTime?` | per-entry `khataDueHarvest(date, month)` line on debits |

## Variants

- farmer (Pay now)
- agent (Collect)

## States

- no entries
- due
- overdue
- settled
- overdue buckets header (A58)

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

## Usage (FA-020 / FA-021 / FA-022)

A58 passes `balancePaise` = the sum of the entries it lists (FA-022 acceptance: the displayed balance equals the displayed entries; every page is fetched), the next due date, bucket pills 0–30 / 31–60 / 61–90 / 90+ as `header`, and `onAction` = Collect (A52 dues).
