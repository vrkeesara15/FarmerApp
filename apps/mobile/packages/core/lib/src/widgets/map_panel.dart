import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

import '../farmers/location_source.dart';
import '../geo/geo.dart';
import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// 1x1 transparent PNG, encoded once.
final Uint8List _transparentPng = img.encodePng(
  img.Image(width: 1, height: 1, numChannels: 4),
);

/// Tile provider that never touches the network: blank tiles over the
/// panel background (tests, goldens, previews).
class BlankTileProvider extends TileProvider {
  /// Creates the provider.
  BlankTileProvider();

  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => MemoryImage(_transparentPng);
}

/// OpenStreetMap raster tiles (no API key; the OSM tile usage policy asks
/// for a proper user agent, set through [MapPanel.userAgentPackageName]).
const String osmTileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

/// How the geofence is drawn on A30 (FA-014): the polygon border (and the
/// meeting point ring) in success or danger colour.
enum GeofenceHighlight {
  /// No decision yet (primary colour, as on A21 / A22).
  none,

  /// Inside: green ring.
  inside,

  /// Outside: danger ring.
  outside,
}

/// Farm boundary map (SPEC 13.1 `MapPanel`, mobile version) over
/// `flutter_map` with OSM tiles.
///
/// Shows the [boundary] as a polygon (or an open line while it is being
/// walked), numbered corner markers, the officer's [currentPosition] with
/// its accuracy ring, and calls [onTap] with the tapped position in tap
/// mode. The camera follows new points. Geofence rings, track lines and
/// visit pins arrive with FA-014 / FA-016 on the same widget.
class MapPanel extends StatefulWidget {
  /// Creates the panel.
  const MapPanel({
    required this.boundary,
    this.closed = true,
    this.center,
    this.currentPosition,
    this.onTap,
    this.interactive = true,
    this.height = 260,
    this.showCorners = true,
    this.tileProvider,
    this.userAgentPackageName = 'in.farmerapp.mitra',
    this.mapController,
    this.geofence = GeofenceHighlight.none,
    this.meetingPoint,
    this.meetingRadiusM,
    super.key,
  });

  /// Boundary ring without the closing point.
  final List<GeoPoint> boundary;

  /// Draw a filled polygon (true) or an open line (walk in progress).
  final bool closed;

  /// Where to look when there are no points yet (village centre, last
  /// fix); India's centre when null.
  final GeoPoint? center;

  /// Officer position (walk mode) with its accuracy ring.
  final GeoFix? currentPosition;

  /// Tap handler (tap-corners mode); null makes taps inert.
  final ValueChanged<GeoPoint>? onTap;

  /// Pan / zoom enabled.
  final bool interactive;

  /// Panel height.
  final double height;

  /// Numbered markers on the corners.
  final bool showCorners;

  /// Tile source override; default is the OSM network provider, tests pass
  /// [BlankTileProvider].
  final TileProvider? tileProvider;

  /// User agent sent to the tile server.
  final String userAgentPackageName;

  /// Optional controller (the panel creates one otherwise).
  final MapController? mapController;

  /// A30 geofence decision: colours the polygon border and the meeting
  /// point ring (success / danger).
  final GeofenceHighlight geofence;

  /// Village meeting point (VV-003), drawn as a ring of [meetingRadiusM].
  final GeoPoint? meetingPoint;

  /// Radius of the meeting point ring in metres.
  final double? meetingRadiusM;

  /// Fallback centre (India).
  static const GeoPoint defaultCenter = GeoPoint(17.4, 78.5);

  /// Zoom used for a single point or the fallback centre.
  static const double pointZoom = 17;

  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  MapController? _ownController;
  bool _ready = false;

  MapController get _controller =>
      widget.mapController ?? (_ownController ??= MapController());

  GeoPoint get _initialCenter => widget.boundary.isNotEmpty
      ? (polygonCentroid(widget.boundary) ?? widget.boundary.last)
      : widget.currentPosition?.point ??
            widget.center ??
            widget.meetingPoint ??
            MapPanel.defaultCenter;

  @override
  void didUpdateWidget(MapPanel old) {
    super.didUpdateWidget(old);
    // Follow the walk (new fixes / points) but never move the camera under
    // the officer's finger while they tap corners.
    final positionChanged =
        old.currentPosition?.point != widget.currentPosition?.point;
    final pointsChanged = old.boundary.length != widget.boundary.length;
    if (_ready &&
        (positionChanged || (pointsChanged && widget.onTap == null))) {
      _follow();
    }
  }

  void _follow() {
    final pts = <GeoPoint>[
      ...widget.boundary,
      if (widget.currentPosition != null) widget.currentPosition!.point,
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _controller.move(_ll(pts.single), MapPanel.pointZoom);
      return;
    }
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts.map(_ll).toList()),
        padding: const EdgeInsets.all(Tokens.space8),
        maxZoom: 18,
      ),
    );
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final ring = widget.boundary.map(_ll).toList(growable: false);
    final fix = widget.currentPosition;
    final ringColor = switch (widget.geofence) {
      GeofenceHighlight.none => p.primary,
      GeofenceHighlight.inside => p.statusSuccess,
      GeofenceHighlight.outside => p.statusDanger,
    };
    final ringWidth = widget.geofence == GeofenceHighlight.none
        ? app.borderWidth + 1
        : app.borderWidth + 3;
    final meeting = widget.meetingPoint;
    final acres = polygonAreaAcres(widget.boundary);
    final semantics = widget.boundary.isEmpty
        ? l10n.mapNoBoundary
        : '${l10n.mapFarmBoundary}, ${l10n.regPointsCount(widget.boundary.length)}, '
              '${l10n.regComputedArea(acres.toStringAsFixed(2))}';

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semantics,
      child: Container(
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: app.tint(p.primaryContainer),
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          border: Border.fromBorderSide(app.borderSide),
        ),
        child: Stack(
          children: <Widget>[
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _ll(_initialCenter),
                initialZoom: MapPanel.pointZoom,
                backgroundColor: app.tint(p.primaryContainer),
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all & ~InteractiveFlag.rotate
                      : InteractiveFlag.none,
                ),
                onTap: widget.onTap == null
                    ? null
                    : (_, latLng) => widget.onTap!(
                        GeoPoint(latLng.latitude, latLng.longitude),
                      ),
                onMapReady: () {
                  _ready = true;
                  if (widget.boundary.length > 1) _follow();
                },
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: osmTileUrlTemplate,
                  userAgentPackageName: widget.userAgentPackageName,
                  tileProvider: widget.tileProvider,
                  tileDisplay: const TileDisplay.instantaneous(),
                ),
                if (ring.length >= 3 && widget.closed)
                  PolygonLayer(
                    polygons: <Polygon<Object>>[
                      Polygon<Object>(
                        points: ring,
                        color: ringColor.withValues(alpha: 0.25),
                        borderColor: ringColor,
                        borderStrokeWidth: ringWidth,
                      ),
                    ],
                  )
                else if (ring.length >= 2)
                  PolylineLayer(
                    polylines: <Polyline<Object>>[
                      Polyline<Object>(
                        points: ring,
                        color: p.primary,
                        strokeWidth: app.borderWidth + 1,
                      ),
                    ],
                  ),
                if (meeting != null && widget.meetingRadiusM != null)
                  CircleLayer(
                    circles: <CircleMarker<Object>>[
                      CircleMarker<Object>(
                        point: _ll(meeting),
                        radius: widget.meetingRadiusM!,
                        useRadiusInMeter: true,
                        color: ringColor.withValues(alpha: 0.15),
                        borderColor: ringColor,
                        borderStrokeWidth: ringWidth,
                      ),
                    ],
                  ),
                if (fix != null)
                  CircleLayer(
                    circles: <CircleMarker<Object>>[
                      CircleMarker<Object>(
                        point: _ll(fix.point),
                        radius: fix.accuracyMetres,
                        useRadiusInMeter: true,
                        color: p.statusInfo.withValues(alpha: 0.15),
                        borderColor: p.statusInfo,
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: <Marker>[
                    if (widget.showCorners)
                      for (var i = 0; i < ring.length; i++)
                        Marker(
                          point: ring[i],
                          width: Tokens.space6,
                          height: Tokens.space6,
                          child: _CornerDot(
                            index: i + 1,
                            label: l10n.mapCorner(i + 1),
                          ),
                        ),
                    if (fix != null)
                      Marker(
                        point: _ll(fix.point),
                        width: Tokens.space6,
                        height: Tokens.space6,
                        child: _PositionDot(label: l10n.mapCurrentPosition),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: Tokens.space2,
              bottom: Tokens.space1,
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(Tokens.radiusChip),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space1,
                    ),
                    child: Text(
                      l10n.mapAttribution,
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.boundary.isEmpty)
              Positioned(
                left: Tokens.space3,
                top: Tokens.space3,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(Tokens.radiusChip),
                      border: Border.fromBorderSide(app.borderSide),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.space3,
                        vertical: Tokens.space1,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.crop_square_outlined,
                            size: Tokens.space4,
                            color: p.textSecondary,
                          ),
                          const SizedBox(width: Tokens.space1),
                          Text(
                            l10n.mapNoBoundary,
                            style: app.text.caption.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CornerDot extends StatelessWidget {
  const _CornerDot({required this.index, required this.label});

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.surface,
          shape: BoxShape.circle,
          border: Border.all(color: p.primary, width: app.borderWidth + 1),
        ),
        child: Text(
          '$index',
          style: app.text.caption.copyWith(
            color: p.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PositionDot extends StatelessWidget {
  const _PositionDot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.app.palette;
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Center(
        child: Container(
          width: Tokens.space4,
          height: Tokens.space4,
          decoration: BoxDecoration(
            color: p.statusInfo,
            shape: BoxShape.circle,
            border: Border.all(color: p.surface, width: 2),
          ),
        ),
      ),
    );
  }
}
