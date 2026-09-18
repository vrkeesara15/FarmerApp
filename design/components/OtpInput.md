# OtpInput

Six single-digit boxes with auto-advance, paste support, backspace navigation and resend timer.

Source: `apps/console/components/ds/OtpInput.tsx` (tests: `OtpInput.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `value` | `string` | controlled digits |
| `onChange` | `(v: string) => void` |  |
| `onComplete` | `(v: string) => void` | fires when all boxes filled — use the argument, not parent state |
| `length` | `number` | default 6 |
| `error` | `string` |  |
| `disabled` | `boolean` |  |
| `resendAfterSeconds` | `number` | default 30; 0 = resend immediately available |
| `onResend` | `() => void` |  |
| `autoFocus` | `boolean` |  |

## Variants

- 6 boxes (default)
- custom length

## States

- default
- filled
- error (danger borders + alert)
- disabled
- resend countdown / resend available

## Accessibility

- Each box has aria-label 'One-time password digit n of 6'
- First box autocomplete=one-time-code for SMS autofill
- Arrow keys and Backspace move between boxes
- Timer region is aria-live=polite

## Tokens used

- `color.border`
- `color.surface`
- `color.text`
- `color.danger`
- `color.primary`
- `radius.input`
- `text.console.heading`
- `font.features (tnum)`

## Flutter

Six digit boxes backed by one hidden text field (SMS autofill + paste work); active box advances as digits arrive; resend countdown then 'Resend OTP'.

Source: `apps/mobile/packages/core/lib/src/widgets/otp_input.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `length` | `int` | default 6 |
| `onCompleted` | `ValueChanged<String>?` | fires when all digits entered |
| `onChanged` | `ValueChanged<String>?` |  |
| `onResend` | `VoidCallback?` | restarts the timer |
| `resendAfter` | `Duration` | default 30 s; Duration.zero shows resend immediately |
| `errorText` | `String?` | danger boxes + message |
| `autofocus / enabled` | `bool` |  |

### Variants

- default

### States

- empty
- partially filled (active box highlighted)
- complete
- error
- countdown running
- resend available
- disabled

### Accessibility

- Each box has `Semantics(label: 'Digit n of 6', value: digit)`.
- Hidden field declares `AutofillHints.oneTimeCode`.
- Resend is a 48 dp icon+text button.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.surface`
- `color.border`
- `color.primary`
- `color.status.danger`
- `color.text.secondary`
- `radius.input`
- `size.primaryButtonHeight`
- `size.touchTargetMin`
- `space.2`
- `space.3`
- `text.mobile.title`
- `text.mobile.label`
- `text.mobile.caption`

### Tests

Widget tests: auto-advance, digit filtering, resend timer, error. Golden: otp_input_{light,sunlight}.png
