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

## Usage (FA-015 / FA-017)

- A31 shows it live: the rows come from `evaluateVisitProof` (`packages/core/lib/src/visits/visit_proof.dart`), the device twin of the server's VV-004 rule, recomputed every second (duration ticks) and on every photo / confirmation. Explanations: geofence `proofGeofenceOverride` / `proofGeofenceOutside`; photo `proofPhotoDone`; duration `visitDurationNeeds(min, minimum)` then `proofDurationDone`.
- A33 shows the same rows at check-out and switches to the server's `score_components` once the pull stores them (server wins). The fifth component (integrity, 10 points) is not a row: a `proofIntegrityIssue` caption appears under the list when it scores 0.
- Row builder shared by both screens: `proofItems()` in `apps/agent/lib/screens/visits/visit_copy.dart`.

## Tests

Golden: proof_checklist_{light,sunlight}.png; in context on `a31_visit_in_progress_*` and `a33_summary_*`.

