# Stepper

Wizard header: 'Step n of N', segmented progress bar and the current step title. Flutter class is `AppStepper` (Flutter's material library already exports `Stepper`).

Source: `apps/mobile/packages/core/lib/src/widgets/app_stepper.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `steps` | `List<String>` | localised titles |
| `currentIndex` | `int` | zero-based |

## Variants

- default

## States

- per segment: done/current (primary) vs upcoming (border tint)

## Accessibility

- `Semantics(label: 'Step n of N: <title>')`.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.primary`
- `color.border`
- `color.text.secondary`
- `radius.pill`
- `space.1`
- `space.2`
- `text.mobile.label`
- `text.mobile.title`

## Tests

Golden: app_stepper_{light,sunlight}.png

