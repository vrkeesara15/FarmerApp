# CameraGuideOverlay

Overlay for the in-app camera: corner-marked leaf frame plus three tips (hold steady, good light, fill the frame). After a rejected photo (FM-004) it lights the tip that fixes the problem and shows the retake line.

Source: `apps/mobile/packages/core/lib/src/widgets/camera_guide_overlay.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `tipKey` | `String?` | `PhotoTipKeys.blurry` lights "hold steady", `PhotoTipKeys.dark` lights "good light", `PhotoTipKeys.ok` shows the good-photo line; null = static overlay. Place above the camera preview in a Stack. |

`CameraGuideOverlay.highlightedTip(key)` returns the lit chip index (0/1/null) for screens that want to mirror it.

## Variants

- default (static)
- with tip (`tipKey` set): retake line under the frame label (key `CameraGuideOverlay.tipMessageKey`), lit chip gets the warning colour and a thicker border

## States

- static
- blurry (`photo.tip.blurry`), dark (`photo.tip.dark`), ok (`photo.tip.ok`)

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

