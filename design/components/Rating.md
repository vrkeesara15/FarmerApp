# Rating

1-5 rating as faces (default, farmer) or stars, each option labelled (Very bad .. Very good).

Source: `apps/mobile/packages/core/lib/src/widgets/rating.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `value` | `int?` | 1-5 |
| `onChanged` | `ValueChanged<int>?` | null = read-only |
| `style` | `RatingStyle` | faces | stars |
| `title` | `String?` | default 'Rate your visit' |

## Variants

- faces
- stars

## States

- unselected
- selected
- read-only

## Accessibility

- Each option `Semantics(button, selected, label: 'n, <label>')`, >= 72 dp tall.
- Faces are outlined Material icons (no emoji).
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.status.danger`
- `color.status.warning`
- `color.status.success`
- `color.secondary`
- `color.primary.container`
- `color.surface`
- `color.border`
- `color.text.muted`
- `radius.chip`
- `space.1`
- `space.2`
- `space.3`
- `space.8`
- `text.mobile.heading`
- `text.mobile.caption`

## Tests

Golden: rating_{light,sunlight}.png

