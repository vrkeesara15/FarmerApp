# VisitScoreBadge

0–100 visit score coloured by status: verified ≥70, partial 40–69, unverified <40 (outline).

Source: `apps/console/components/ds/VisitScoreBadge.tsx` (tests: `VisitScoreBadge.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `score` | `number` | clamped 0..100 |
| `showLabel` | `boolean` | default true |
| `size` | `'sm' | 'md'` |  |

## Variants

- verified (success container)
- partial (warning container)
- unverified (danger outline)

## States

- default

## Accessibility

- role=img with aria-label 'Visit score n of 100 — Verified'
- Status word shown by default so colour is not the only cue

## Tokens used

- `color.visit.verified`
- `color.visit.partial`
- `color.visit.unverified`
- `color.status.successContainer`
- `color.status.warningContainer`
- `radius.pill`
- `font.features (tnum)`

## Notes

`visitStatusFor(score)` is exported for use in tables and maps.

## Flutter

Score pill 0-100. >= 70 verified (success, filled), 40-69 partial (warning, filled), < 40 unverified (danger outline).

Source: `apps/mobile/packages/core/lib/src/widgets/visit_score_badge.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `score` | `int` | 0-100; `VisitStatus.fromScore` exposes the thresholds |

### Variants

- verified
- partial
- unverified

### States

- static

### Accessibility

- `Semantics(label: '<status>, Score n of 100')`.
- Status is conveyed by icon + text, not colour alone.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.visit.verified`
- `color.visit.partial`
- `color.visit.unverified`
- `color.status.successContainer`
- `color.status.warningContainer`
- `color.surface`
- `radius.pill`
- `space.1`
- `space.3`
- `space.4`
- `text.mobile.label`
- `text.mobile.caption`

### Tests

Widget tests: thresholds 70/40 and labels. Golden: visit_score_badge_{light,sunlight}.png
