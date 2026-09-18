# MapPanel

Farm boundary map (mobile version): polygon or open line, numbered corners, the officer's position with an accuracy ring, tap-to-add corners. Geofence ring, officer track line and visit pins (FA-014 / FA-016) extend this same widget; the console version is separate (React).

Source: `apps/mobile/packages/core/lib/src/widgets/map_panel.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`). Built on `flutter_map` 8 with OpenStreetMap raster tiles (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`, no API key, user agent `in.farmerapp.mitra`); tiles are cached by the OS HTTP cache. Geometry helpers are pure Dart in `packages/core/lib/src/geo/geo.dart` (`GeoPoint`, `polygonAreaAcres` spherical shoelace, `polygonCentroid`, `isSelfIntersecting`, `polygonToGeoJson` / `polygonFromGeoJson`, `areaDiffersBeyondTolerance`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `boundary` | `List<GeoPoint>` | ring without the closing point |
| `closed` | `bool` | filled polygon (default) or open polyline while walking |
| `center` | `GeoPoint?` | where to look with no points (last fix, village); India centre fallback |
| `currentPosition` | `GeoFix?` | officer dot + accuracy circle (metres) |
| `onTap` | `ValueChanged<GeoPoint>?` | tap-corners mode; null = inert |
| `interactive` | `bool` | pan / zoom (rotation is always off) |
| `height` | `double` | 260 default; 140 as a mini map on A21e / A22 |
| `showCorners` | `bool` | numbered markers |
| `tileProvider` | `TileProvider?` | `BlankTileProvider` in tests and goldens (no network) |
| `mapController` | `MapController?` | optional |
| `geofence` | `GeofenceHighlight` | A30: `inside` draws the polygon border / meeting ring in success colour (+2 dp), `outside` in danger; `none` = primary |
| `meetingPoint` | `GeoPoint?` | village meeting point (VV-003) |
| `meetingRadiusM` | `double?` | radius of the meeting point ring (m) |

The camera follows new points (single point → zoom 17; two or more → fit bounds with 32 dp padding, max zoom 18).

## Variants

- capture (interactive, walk or tap)
- mini (non-interactive, 140 dp)

## States

- empty (`mapNoBoundary` pill)
- open line (walk in progress)
- closed polygon
- with position + accuracy ring

## Accessibility

- Container node "Farm boundary, n points, Measured area x acres" (or "No boundary yet"), explicit child nodes: "Corner n" per marker, "Your position" for the dot.
- Attribution caption `mapAttribution` always visible (OSM policy).
- Colours from `AppThemeData.palette`; Sunlight: no tint, 2 dp borders.

## Tokens used

- `color.primary` (polygon, corners), `color.primary.container` (ground while tiles load), `color.status.info` (position), `color.surface`, `color.border`, `color.text.secondary`
- `radius.card`, `radius.chip`
- `space.1..8`, `size.icon`
- `text.mobile.caption`

## Tests

`packages/core/test/widgets/map_panel_test.dart`, goldens `map_panel_{light,sunlight}.png`; used on A21b / A21e / A22 / A23.
