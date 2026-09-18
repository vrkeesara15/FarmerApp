# TreatmentCard

Organic/chemical tag, name, active ingredient, dose per acre and per 15 L tank, pre-harvest interval, PPE pictograms with labels.

Source: `apps/mobile/packages/core/lib/src/widgets/treatment_card.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `name` | `String` |  |
| `kind` | `TreatmentKind` | organic | chemical |
| `activeIngredient` | `String?` |  |
| `dosePerAcre / dosePerTank` | `String` | pre-formatted |
| `safetyIntervalDays` | `int?` |  |
| `ppe` | `Set<Ppe>` | gloves | mask | goggles |

## Variants

- organic
- chemical

## States

- with/without safety interval and PPE

## Accessibility

- PPE icons each have a text label; dose tiles pair icon, label and value.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.background`
- `color.border`
- `color.primary`
- `color.status.success`
- `color.status.successContainer`
- `color.status.info`
- `color.status.infoContainer`
- `color.status.warning`
- `radius.card`
- `radius.input`
- `radius.pill`
- `space.1..4`
- `text.mobile.heading`
- `text.mobile.body`
- `text.mobile.label`
- `text.mobile.caption`

## Tests

Golden: treatment_card_{light,sunlight}.png

