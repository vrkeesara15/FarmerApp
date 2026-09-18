# StageTimeline

Horizontal sowing -> harvest timeline; done steps filled, current enlarged, upcoming outlined.

Source: `apps/mobile/packages/core/lib/src/widgets/stage_timeline.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `stages` | `List<String>` | localised labels |
| `currentIndex` | `int` |  |

## Variants

- default

## States

- done / current / upcoming per step

## Accessibility

- Each step has `Semantics(label, selected)`; done steps show a check icon.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.primary`
- `color.primary.on`
- `color.border`
- `color.surface`
- `color.text`
- `color.text.secondary`
- `space.1`
- `space.3`
- `space.4`
- `space.6`
- `text.mobile.caption`

## Tests

Golden: stage_timeline_{light,sunlight}.png

