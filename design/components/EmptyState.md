# EmptyState

Illustration/icon, one-line help and an optional action.

Source: `apps/console/components/ds/EmptyState.tsx` (tests: `EmptyState.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `title` | `string` | default 'Nothing here yet' |
| `help` | `string` |  |
| `illustration` | `ReactNode` |  |
| `action` | `ReactNode` | typically AppButton |

## Variants

- default icon
- custom illustration
- with action

## States

- default

## Accessibility

- role=status

## Tokens used

- `color.surface`
- `color.border`
- `color.background`
- `color.text.muted`
- `radius.card`
- `radius.pill`
- `text.console.heading`
- `text.console.body`

## Flutter

Pictogram in a circle, title, one-line help, optional action.

Source: `apps/mobile/packages/core/lib/src/widgets/empty_state.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `icon` | `IconData` | default inbox |
| `title / help` | `String?` | defaults from l10n |
| `actionLabel + onAction` | `` | button shown only with both |

### Variants

- default
- with action

### States

- static

### Accessibility

- Action is a 48 dp AppButton with icon + text.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.primary`
- `color.primary.container`
- `color.border`
- `color.text.secondary`
- `space.2`
- `space.4`
- `space.6`
- `space.12`
- `text.mobile.heading`
- `text.mobile.body`

### Tests

Golden: empty_state_{light,sunlight}.png
