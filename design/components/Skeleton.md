# Skeleton

Pulsing placeholder blocks; SkeletonText renders n lines.

Source: `apps/console/components/ds/Skeleton.tsx` (tests: `Skeleton.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `className` | `string` | size with width/height utilities |
| `announce` | `boolean` | role=status + aria-label 'Loading' (one per region) |
| `lines` | `number` | SkeletonText only |

## Variants

- block
- text lines

## States

- default

## Accessibility

- aria-hidden by default; use announce on the outermost skeleton only

## Tokens used

- `color.border`
- `radius.input`

## Flutter

Static (non-shimmering) loading placeholders: `Skeletons.line`, `Skeletons.card`, `Skeletons.list(count)`.

Source: `apps/mobile/packages/core/lib/src/widgets/skeletons.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `Skeletons.line(width, height)` | `` | single line |
| `Skeletons.card()` | `` | avatar + two lines |
| `Skeletons.list(count)` | `` | stacked cards |

### Variants

- line
- card
- list

### States

- static

### Accessibility

- Wrapped in `Semantics(label: 'Loading content')` with children excluded.
- No animation: cheap on 2 GB devices and no motion issues.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.border`
- `color.surface`
- `radius.chip`
- `radius.card`
- `space.2`
- `space.3`
- `space.4`
- `space.12`

### Tests

Golden: skeletons_{light,sunlight}.png
