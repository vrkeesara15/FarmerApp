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
| `provisionalState` | `bool?` | M6: overrides the provisional look (an LLM answer can be medium confidence and still provisional); null derives it from `confidence == low` |
| `onSymptomTap` | `ValueChanged<int>?` | M6: makes the symptom rows 48 dp tappable ("check these signs": the user ticks what they see; keys `diagnosis-symptom-<i>`) |

## Variants

- high confidence
- provisional

## States

- default
- provisional (dashed border, no buy actions expected by the screen)

## Usage (M6)

`DiagnosisResultView` (`lib/src/widgets/diagnosis_result_view.dart`) composes the card with the headline for `message_key`, Organic / Chemical `TreatmentCard`s (tank pictogram, PHI, PPE, safety text), ranked `ProductCard`s at the store (with `OwnBrandBadge`), cultural practices, the F27 updated banner and the earlier answers; `DiagnosisActionBar` holds the one-tap actions. Order buttons exist only when `Diagnosis.showBuy` (server `can_buy`, not provisional, answered / confirmed / corrected) — SPEC 3.4. Used by F25–F28 and A43; tests `test/widgets/diagnosis_result_view_test.dart`, goldens `f25_result_*`, `f26_provisional_*`, `f28_not_a_plant_*`, `a43_result_*`.

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

