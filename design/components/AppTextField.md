# AppTextField

Labelled text input with helper, error and optional prefix (e.g. +91 for phone).

Source: `apps/console/components/ds/AppTextField.tsx` (tests: `AppTextField.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `label` | `string` | required, rendered as <label> |
| `helper` | `string` | shown below when no error |
| `error` | `string` | marks aria-invalid, replaces helper, role=alert |
| `prefix` | `ReactNode` | visual prefix |
| `suffix` | `ReactNode` |  |
| `phone` | `boolean` | +91 prefix, type=tel, numeric inputmode |
| `optional` | `boolean` | appends (Optional) |
| `disabled` | `boolean` |  |
| `...InputHTMLAttributes` | `` | value, onChange, name, etc. |

## Variants

- text
- phone (+91 prefix)
- with suffix

## States

- default
- focus (ring)
- error (danger border + message)
- disabled (50% opacity)

## Accessibility

- label linked via htmlFor
- helper/error linked via aria-describedby
- error announced via role=alert
- aria-invalid on error

## Tokens used

- `color.border`
- `color.surface`
- `color.text`
- `color.text.secondary`
- `color.text.muted`
- `color.danger`
- `radius.input`
- `text.console.body`
- `text.console.small`

## Flutter

Labelled text input with helper, error and optional fixed +91 prefix.

Source: `apps/mobile/packages/core/lib/src/widgets/app_text_field.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `label` | `String` | always-visible label above the input |
| `controller` | `TextEditingController?` |  |
| `helperText / errorText / hintText` | `String?` | error turns the border danger |
| `indiaPhone` | `bool` | +91 prefix, numeric keyboard, digits only, 10 max |
| `enabled / autofocus` | `bool` |  |
| `keyboardType / textInputAction / maxLength` | `` |  |
| `onChanged / onSubmitted` | `ValueChanged<String>?` |  |
| `prefixIcon` | `IconData?` |  |

### Variants

- default
- phone (+91)

### States

- default
- focused (primary border, +1 dp)
- error
- disabled

### Accessibility

- Label is a real Text above the field (not a floating placeholder) so it stays readable at 16 sp.
- Min height 56 dp.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.surface`
- `color.border`
- `color.primary`
- `color.status.danger`
- `color.text.secondary`
- `color.text.muted`
- `radius.input`
- `border.width`
- `space.2`
- `space.3`
- `space.4`
- `text.mobile.body`
- `text.mobile.label`
- `text.mobile.caption`

### Tests

Golden: app_text_field_{light,sunlight}.png
