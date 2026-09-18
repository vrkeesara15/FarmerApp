# DiagnosisResultCard

Problem name (+ local name), ConfidenceBand, symptom checklist; provisional state has a dashed border and the 'expert will confirm within 24 hours' note.

Source: `apps/mobile/packages/core/lib/src/widgets/diagnosis_result_card.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `problemName` | `String` |  |
| `localName` | `String?` |  |
| `confidence` | `ConfidenceLevel` | high | medium | low (provisional) |
| `symptoms` | `List<SymptomCheck>` | label + present |
| `image` | `ImageProvider?` |  |

## Variants

- high confidence
- provisional

## States

- default
- provisional (dashed border, no buy actions expected by the screen)

## Accessibility

- Symptom rows use checkbox icons paired with text.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.border`
- `color.primary`
- `color.primary.container`
- `color.confidence.low`
- `color.status.success`
- `color.text.muted`
- `color.text.secondary`
- `radius.card`
- `radius.input`
- `space.1..4`
- `space.12`
- `text.mobile.title`
- `text.mobile.heading`
- `text.mobile.body`
- `text.mobile.caption`

## Tests

Golden: diagnosis_result_card_{light,sunlight}.png

