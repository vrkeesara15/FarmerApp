# ProofChecklist

Tick/cross rows for geofence, photo, farmer confirmed and duration, each with an explanation when missing.

Source: `apps/mobile/packages/core/lib/src/widgets/proof_checklist.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `items` | `List<ProofItem>` | kind (ProofKind), satisfied, explanation? |

## Variants

- default

## States

- row done / row missing

## Accessibility

- Row `Semantics(label: '<proof>: Done|Missing')`; result icon paired with 'Done'/'Missing' text.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.border`
- `color.status.success`
- `color.status.danger`
- `color.text.secondary`
- `radius.card`
- `space.1..3`
- `text.mobile.body`
- `text.mobile.caption`

## Tests

Golden: proof_checklist_{light,sunlight}.png

