import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/farmers_harness.dart';
import '../helpers/harness.dart';

/// MapPanel over blank tiles: polygon vs open line, corner markers,
/// position dot, tap callback, semantics with the measured area.
void main() {
  Widget panel({
    List<GeoPoint> boundary = const <GeoPoint>[],
    bool closed = true,
    GeoFix? position,
    ValueChanged<GeoPoint>? onTap,
  }) => harness(
    MapPanel(
      boundary: boundary,
      closed: closed,
      currentPosition: position,
      onTap: onTap,
      tileProvider: BlankTileProvider(),
    ),
  );

  testWidgets('empty boundary shows the hint and attribution', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(panel());
    await tester.pump();
    expect(find.text('No boundary yet'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.bySemanticsLabel('No boundary yet'), findsOneWidget);
  });

  testWidgets('a closed ring renders a polygon with numbered corners', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(panel(boundary: squareHectare));
    await tester.pump();
    expect(find.byType(PolygonLayer), findsOneWidget);
    expect(find.byType(PolylineLayer), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.bySemanticsLabel('Corner 3'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('Farm boundary, 4 points, Measured area 2.4'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an open walk renders a line and the position dot', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      panel(
        boundary: squareHectare.take(3).toList(),
        closed: false,
        position: fixAt(offsetPoint(10, 90), accuracy: 8),
      ),
    );
    await tester.pump();
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.byType(PolygonLayer), findsNothing);
    expect(find.byType(CircleLayer), findsOneWidget);
    expect(find.bySemanticsLabel('Your position'), findsOneWidget);
  });

  testWidgets('tapping the map reports a position', (tester) async {
    usePhoneSurface(tester);
    GeoPoint? tapped;
    await tester.pumpWidget(panel(onTap: (p) => tapped = p));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, isNotNull);
    expect(tapped!.latitude, closeTo(MapPanel.defaultCenter.latitude, 0.01));
  });
}
