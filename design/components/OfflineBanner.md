# OfflineBanner

Full-width warning strip shown while offline.

Source: `apps/mobile/packages/core/lib/src/widgets/offline_banner.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`). Live wrapper: `lib/src/widgets/sync_live.dart` `OfflineBannerLive` renders the banner only while `offlineProvider` is true (connectivity via `connectivity_plus`, FA-025 / NF-002) and nothing otherwise; place it at the top of the app shell above the screen body.

## Props

| Prop | Type | Notes |
|---|---|---|
| `message` | `String?` | override default copy |

## Variants

- default

## States

- static

## Accessibility

- `Semantics(liveRegion)` so screen readers announce it.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.status.warning`
- `color.status.warningContainer`
- `border.width`
- `space.2`
- `space.4`
- `text.mobile.label`

## Tests

Golden: offline_banner_{light,sunlight}.png

