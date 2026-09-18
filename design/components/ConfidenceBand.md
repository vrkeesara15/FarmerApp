# ConfidenceBand

Diagnosis confidence chip: High = success, Medium = warning, Low/Provisional = neutral grey with dashed border.

Source: `apps/console/components/ds/ConfidenceBand.tsx` (tests: `ConfidenceBand.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `level` | `'high' | 'medium' | 'low'` |  |
| `provisional` | `boolean` | low shows 'Provisional' |

## Variants

- high
- medium
- low (dashed neutral)
- low + provisional

## States

- default

## Accessibility

- Words, not just colour
- data-level attribute

## Tokens used

- `color.confidence.high`
- `color.confidence.medium`
- `color.confidence.low`
- `color.status.successContainer`
- `color.status.warningContainer`
- `radius.chip`
- `text.console.small`

## Flutter

Confidence pill: high = success, medium = warning, low/provisional = neutral grey with dashed border.

Source: `apps/mobile/packages/core/lib/src/widgets/confidence_band.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `level` | `ConfidenceLevel` | high | medium | low |

### Variants

- high
- medium
- low (dashed)

### States

- static

### Accessibility

- Icon + text; `Semantics(label)`.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.confidence.high`
- `color.confidence.medium`
- `color.confidence.low`
- `color.status.successContainer`
- `color.status.warningContainer`
- `color.surface`
- `radius.pill`
- `border.width`
- `space.1`
- `space.3`
- `text.mobile.label`

### Tests

Golden: confidence_band_{light,sunlight}.png
