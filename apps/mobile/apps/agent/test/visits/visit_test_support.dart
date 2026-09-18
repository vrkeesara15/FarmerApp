import 'dart:math';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../duty/duty_test_support.dart';
import '../farmers/agent_harness.dart';

/// A fix [east] / [north] metres from the test farm origin.
LocationFix fixNear(DateTime at, {double east = 50, double north = 50}) {
  final p = offsetPoint(east, north);
  return LocationFix(
    point: p,
    accuracyM: 8,
    time: at,
    bearing: 0,
    provider: 'fused',
  );
}

/// Village, farmer `f-1` with the 100 m square farm, policy accepted and
/// (unless [onDuty] is false) a duty session; the GPS then sits at
/// [east] / [north] of the farm origin.
Future<void> seedVisitWorld(
  AgentDeps deps, {
  bool onDuty = true,
  double east = 50,
  double north = 50,
}) async {
  deps.now = dutyT0;
  await seedVillage(deps.db);
  await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
  await acceptPolicy(deps);
  if (onDuty) await seedOnDuty(deps);
  deps.sampler.initial = fixNear(deps.now, east: east, north: north);
}

/// Queues a check-in (and optionally photo / confirmation) without the UI.
Future<String> seedVisit(
  AgentDeps deps, {
  double east = 50,
  double north = 50,
  String? note,
}) async {
  deps.sampler.initial = fixNear(deps.now, east: east, north: north);
  final c = deps.container();
  final flow = c.read(visitFlowProvider);
  final farm = (await c.read(farmerRepositoryProvider).farm('farm-f-1'))!.farm;
  final pre = await flow.precheck(farm: farm);
  final out = await flow.checkIn(
    farmerId: 'f-1',
    farmId: 'farm-f-1',
    villageId: 'village-1',
    purpose: VisitPurpose.scouting,
    precheck: pre,
    overrideNote: note,
  );
  c.dispose();
  return out.visitId!;
}

/// The container behind the running app.
ProviderContainer appContainer(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

/// Scrolls the first scrollable until [finder] is visible and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A photo-like JPEG (gradient, sharp blades, noise) that passes the
/// NF-004 blur / darkness gate.
Uint8List testJpeg({int width = 640, int height = 480, int seed = 1}) {
  final image = img.Image(width: width, height: height);
  final rnd = Random(seed);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        (60 + 80 * y / height).round(),
        (120 + 60 * (1 - y / height)).round(),
        (40 + 40 * y / height).round(),
      );
    }
  }
  for (var i = 0; i < 400; i++) {
    final cx = rnd.nextInt(width);
    final cy = rnd.nextInt(height);
    final len = 10 + rnd.nextInt(width ~/ 12);
    final a = rnd.nextDouble() * pi;
    img.drawLine(
      image,
      x1: cx,
      y1: cy,
      x2: (cx + len * cos(a)).round(),
      y2: (cy + len * sin(a)).round(),
      color: img.ColorRgb8(
        20 + rnd.nextInt(80),
        80 + rnd.nextInt(140),
        20 + rnd.nextInt(60),
      ),
      thickness: 1 + rnd.nextInt(4),
    );
  }
  img.noise(image, 8, random: rnd);
  return img.encodeJpg(image, quality: 92);
}
