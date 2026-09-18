import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:farmerapp_core/farmerapp_core.dart';

/// Settable clock injected into the outbox and the engine.
class FakeClock {
  /// Starts at [now].
  FakeClock(this.now);

  /// Current time (UTC).
  DateTime now;

  /// As a [Clock].
  DateTime call() => now;

  /// Moves time forward.
  void advance(Duration d) => now = now.add(d);
}

/// Deterministic op ids (`op-0001`, ...).
class SeqIds {
  int _n = 0;

  /// Next id.
  String call() => 'op-${(++_n).toString().padLeft(4, '0')}';
}

/// Sunday 2026-09-20 06:00 IST as UTC.
final DateTime t0 = DateTime.utc(2026, 9, 20, 0, 30);

/// Fresh in-memory database.
AppDatabase newDb() => AppDatabase(NativeDatabase.memory());

/// Engine over [db] and [api] with the test clock and a fixed seed.
SyncEngine engineFor(
  AppDatabase db,
  SyncApi api, {
  FakeClock? clock,
  Random? random,
  FileReader? readFile,
  int batchSize = maxOpsPerSync,
  Backoff backoff = const Backoff(),
}) => SyncEngine(
  db: db,
  api: api,
  deviceId: () async => 'device-1',
  clock: clock?.call,
  random: random ?? Random(1),
  readFile: readFile,
  batchSize: batchSize,
  backoff: backoff,
);

/// Outbox over [db] with the test clock and sequential ids.
Outbox outboxFor(AppDatabase db, {FakeClock? clock, SeqIds? ids}) =>
    Outbox(db, clock: clock?.call, ids: ids?.call);

/// A farmer payload.
Map<String, Object?> farmerPayload(int n, {String? phone}) => <String, Object?>{
  'phone': phone ?? '+9198765${n.toString().padLeft(5, '0')}',
  'name': 'Farmer $n',
  'village_id': 'village-1',
  'landmark': 'near the temple',
  'language': 'te',
  'preferred_language': 'te',
  'land_ownership': 'own',
  'source': 'field_officer',
  'phone_verified': true,
  'consent_marketing': n.isEven,
};

/// A farm payload with a GeoJSON polygon.
Map<String, Object?> farmPayload(String farmerId, {List<Object?>? photos}) =>
    <String, Object?>{
      'farmer_id': farmerId,
      'name': 'Home farm',
      'boundary': <String, Object?>{
        'type': 'Polygon',
        'coordinates': <Object?>[
          <Object?>[
            <double>[78.4, 17.4],
            <double>[78.41, 17.4],
            <double>[78.41, 17.41],
            <double>[78.4, 17.41],
            <double>[78.4, 17.4],
          ],
        ],
      },
      'area_acres': 2.5,
      'soil': 'black',
      'irrigation': 'borewell',
      'ownership': 'own',
      'photos': photos ?? const <Object?>[],
    };

/// A crop plot payload.
Map<String, Object?> cropPlotPayload(String farmId) => <String, Object?>{
  'farm_id': farmId,
  'crop_id': 'crop-cotton',
  'variety': 'Bt',
  'season': 'kharif',
  'sowing_date': '2026-06-15',
  'stage': 'vegetative',
  'area_acres': 1.5,
};

/// Deterministic pseudo-photo bytes.
Uint8List photoBytes(int length, {int seed = 7}) {
  final rng = Random(seed);
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rng.nextInt(256)),
  );
}
