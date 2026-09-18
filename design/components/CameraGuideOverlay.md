# CameraGuideOverlay

Static overlay for the in-app camera: corner-marked leaf frame plus three tips (hold steady, good light, fill the frame).

Source: `apps/mobile/packages/core/lib/src/widgets/camera_guide_overlay.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `(none)` | `` | place above the camera preview in a Stack |

## Variants

- default

## States

- static

## Accessibility

- Overlay `Semantics(label: 'Place the leaf inside the frame')`; tips are icon + text chips on a translucent scrim for contrast.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.primary.on`
- `color.text (scrim)`
- `border.width`
- `radius.chip`
- `space.1..4`
- `space.8`
- `text.mobile.body`
- `text.mobile.caption`

## Tests

Golden: camera_guide_overlay_{light,sunlight}.png

