# ErrorState

Error panel with optional technical detail and retry.

Source: `apps/console/components/ds/ErrorState.tsx` (tests: `ErrorState.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `title` | `string` |  |
| `help` | `string` |  |
| `detail` | `string` | e.g. problem.detail |
| `onRetry` | `() => void` |  |
| `retrying` | `boolean` |  |

## Variants

- with/without retry

## States

- default
- retrying (button loading)

## Accessibility

- role=alert
- Retry is an AppButton (secondary)

## Tokens used

- `color.danger`
- `color.status.dangerContainer`
- `radius.card`
- `text.console.heading`
- `text.console.body`
- `text.console.small`

## Flutter

Danger pictogram, title, help and a 'Try again' secondary button.

Source: `apps/mobile/packages/core/lib/src/widgets/error_state.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `title / help` | `String?` | defaults from l10n |
| `onRetry` | `VoidCallback?` | button hidden when null |

### Variants

- default

### States

- with retry
- without retry

### Accessibility

- Retry is icon + text, 48 dp.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.status.danger`
- `color.status.dangerContainer`
- `color.text.secondary`
- `border.width`
- `space.2`
- `space.4`
- `space.6`
- `space.12`
- `text.mobile.heading`
- `text.mobile.body`

### Tests

Golden: error_state_{light,sunlight}.png
