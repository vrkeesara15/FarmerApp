# DutyToggle

Large card with On duty / Off duty switch, elapsed time and the 'location is on only while you are on duty' note (FA-010).

Source: `apps/mobile/packages/core/lib/src/widgets/duty_toggle.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `onDuty` | `bool` | required |
| `onChanged` | `ValueChanged<bool>?` | null disables |
| `elapsed` | `Duration` | shown as 'On duty for H:MM' when on duty |
| `loading` | `bool` | spinner replaces the switch; taps ignored |
| `blockedReason` | `String?` | FA-011: shown under the card in warning colour with a lock icon; the switch is disabled while set ("Accept the location policy to go on duty") |
| `blockedActionLabel` | `String?` | label of the tertiary link shown with the reason ("Review policy") |
| `onBlockedAction` | `VoidCallback?` | tap handler of that link (A10 → A05) |

## Variants

- off duty
- on duty

## States

- default
- loading
- disabled
- blocked (reason + "Review policy" link; A10 while the location policy version is not accepted)

## Accessibility

- `Semantics(toggled, label)`; whole card is tappable (>= 48 dp).
- Location note is always visible so tracking is never hidden.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.status.success`
- `color.status.successContainer`
- `color.status.warning` (blocked reason)
- `color.text.muted` (blocked action line)
- `color.text.secondary`
- `color.primary`
- `color.border`
- `radius.card`
- `space.1..4`
- `space.8`
- `text.mobile.heading`
- `text.mobile.body`
- `text.mobile.label`
- `text.mobile.caption`

## Tests

Widget tests: off/on/elapsed/toggle/loading/blocked. Golden: duty_toggle_{light,sunlight}.png (off, on, loading, blocked). Wired on A10 by `DutyController` (design/screens/A10.md).

