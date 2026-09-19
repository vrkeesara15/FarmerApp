import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../duty/duty_harness.dart';
import '../photo/synthetic_images.dart';

/// FA-014 .. FA-017 write path against the scripted [FakeSyncApi]: duty
/// gate, check-in payloads inside / outside, in-app photo op with EXIF,
/// capture and check-out ops, server-owned score on pull and conflict,
/// `outside_geofence` rejection and retry from the farm, FA-016 channels.
void main() {
  late DutyDeps deps;
  late FakeCameraSource camera;
  late MemoryPhotoStore photos;
  late FakeVisitConfirmApi confirmApi;
  late FakeConnectivityMonitor connectivity;
  late FakeTenantSettingsApi settingsApi;
  late ProviderContainer c;

  const farmerId = 'farmer-1';
  const farmId = 'farm-1';

  setUp(() async {
    deps = DutyDeps();
    camera = FakeCameraSource();
    photos = MemoryPhotoStore();
    confirmApi = FakeVisitConfirmApi(clock: deps.clock.call);
    connectivity = FakeConnectivityMonitor();
    settingsApi = FakeTenantSettingsApi();
    c = ProviderContainer(
      overrides: <Override>[
        ...deps.overrides(),
        tenantSettingsApiProvider.overrideWithValue(settingsApi),
        cameraSourceProvider.overrideWithValue(camera),
        photoStoreProvider.overrideWithValue(photos),
        visitConfirmApiProvider.overrideWithValue(confirmApi),
        connectivityMonitorProvider.overrideWithValue(connectivity),
        fileReaderProvider.overrideWithValue(
          (path) async => photos.files[path]!,
        ),
      ],
    );
    final entities = LocalEntities(deps.db);
    await entities.write(
      SyncEntities.farmer,
      farmerId,
      <String, Object?>{'name': 'Ramesh', 'phone': '+919876543210'},
      version: 1,
      dirty: false,
      now: dutyT0,
    );
    // 100 m square at the origin.
    await entities.write(
      SyncEntities.farm,
      farmId,
      <String, Object?>{
        'farmer_id': farmerId,
        'boundary': polygonToGeoJson(<GeoPoint>[
          fixAt(dutyT0).point,
          fixAt(dutyT0, east: 100).point,
          fixAt(dutyT0, east: 100, north: 100).point,
          fixAt(dutyT0, north: 100).point,
        ]),
      },
      version: 1,
      dirty: false,
      now: dutyT0,
    );
  });

  tearDown(() async {
    c.dispose();
    await connectivity.dispose();
    await deps.dispose();
  });

  VisitFlow flow() => c.read(visitFlowProvider);

  Future<Farm> farm() async =>
      (await deps.db.select(deps.db.farms).get()).single;

  Future<void> goOnDuty() async {
    await acceptPolicy(c);
    deps.sampler.initial = fixAt(dutyT0, east: 50, north: 50);
    expect(
      await c.read(dutyControllerProvider.notifier).goOnDuty(),
      DutyStartResult.started,
    );
  }

  Future<List<OutboxRow>> visitOps() async =>
      (await outboxRows(deps.db))
          .where((o) => o.entity.startsWith('visit'))
          .toList();

  Future<String> checkInInside() async {
    deps.sampler.initial = fixAt(dutyT0, east: 50, north: 50);
    final pre = await flow().precheck(farm: await farm());
    final out = await flow().checkIn(
      farmerId: farmerId,
      farmId: farmId,
      purpose: VisitPurpose.scouting,
      precheck: pre,
    );
    expect(out.result, CheckInResult.started);
    return out.visitId!;
  }

  test('start visit is blocked while off duty: no op, no row', () async {
    deps.sampler.initial = fixAt(dutyT0, east: 50, north: 50);
    final pre = await flow().precheck(farm: await farm());
    expect(pre.allowed, isTrue);
    final out = await flow().checkIn(
      farmerId: farmerId,
      farmId: farmId,
      purpose: VisitPurpose.advisory,
      precheck: pre,
    );
    expect(out.result, CheckInResult.offDuty);
    expect(await visitOps(), isEmpty);
    expect(await deps.db.select(deps.db.visits).get(), isEmpty);
  });

  test('check-in inside: visit create op with fix, integrity and client id; '
      'optimistic row with the pre-check', () async {
    await goOnDuty();
    final id = await checkInInside();
    final ops = await visitOps();
    expect(ops, hasLength(1));
    final op = ops.single;
    expect('${op.entity}/${op.action}', 'visit/create');
    expect(op.entityId, id);
    final p = SyncStore.payloadOf(op);
    expect(p['farmer_id'], farmerId);
    expect(p['farm_id'], farmId);
    expect(p['purpose'], 'scouting');
    expect(p['checkin_at'], dutyT0.toIso8601String());
    expect((p['checkin_point']! as Map)['accuracy_m'], 8);
    expect(p['device_integrity'], <String, Object?>{
      'is_mock': false,
      'is_rooted': false,
      'clock_drift_s': 0,
    });
    expect(p['client_visit_id'], id);
    expect(p.containsKey('override_note'), isFalse);
    final row = await c.read(visitRepositoryProvider).visit(id);
    expect(row!.precheckResult, 'inside');
    expect(row.precheckDistanceM, 0);
    expect(row.dirty, isTrue);
    expect(row.status, 'open');
  });

  test(
    'check-in outside: no op without a note; op with override_note',
    () async {
      await goOnDuty();
      deps.sampler.initial = fixAt(dutyT0, east: 600, north: 50);
      final pre = await flow().precheck(farm: await farm());
      expect(pre.check!.outcome, GeofenceOutcome.outside);
      expect(pre.check!.distanceM, closeTo(500, 2));
      expect(pre.check!.radiusM, 150);
      final none = await flow().checkIn(
        farmerId: farmerId,
        farmId: farmId,
        purpose: VisitPurpose.meeting,
        precheck: pre,
        overrideNote: '   ',
      );
      expect(none.result, CheckInResult.needsOverride);
      expect(await visitOps(), isEmpty);
      final out = await flow().checkIn(
        farmerId: farmerId,
        farmId: farmId,
        purpose: VisitPurpose.meeting,
        precheck: pre,
        overrideNote: 'Met at the market',
      );
      expect(out.result, CheckInResult.started);
      final p = SyncStore.payloadOf((await visitOps()).single);
      expect(p['override_note'], 'Met at the market');
      final detail = await c.read(visitRepositoryProvider).detail(out.visitId!);
      expect(detail!.geofenceResult, GeofenceResults.override);
      expect(detail.proofAt(deps.clock.now).components['geofence'], 0);
    },
  );

  test('cached tenant radius drives the pre-check', () async {
    await c
        .read(visitRepositoryProvider)
        .saveSettings(const VisitSettings(geofenceRadiusM: 50));
    deps.sampler.initial = fixAt(dutyT0, east: 200, north: 50);
    final pre = await flow().precheck(farm: await farm());
    expect(pre.check!.outcome, GeofenceOutcome.outside);
    expect(pre.check!.radiusM, 50);
  });

  test('fetched tenant settings (GET /v1/settings/public) drive the '
      'pre-check and the proof minimum', () async {
    deps.sampler.initial = fixAt(dutyT0, east: 200, north: 50);
    // SPEC default 150 m: 100 m past the farm edge is inside.
    var pre = await flow().precheck(farm: await farm());
    expect(pre.check!.outcome, GeofenceOutcome.inside);
    expect(pre.check!.radiusM, 150);

    settingsApi.settings = const PublicTenantSettings(
      geofenceRadiusM: 60,
      minVisitDurationS: 900,
    );
    await c.read(tenantSettingsSyncProvider).pull();
    pre = await flow().precheck(farm: await farm());
    expect(pre.check!.outcome, GeofenceOutcome.outside);
    expect(pre.check!.radiusM, 60);
    expect(pre.settings.minVisitDurationS, 900);
    expect((await c.read(visitSettingsProvider.future)).geofenceRadiusM, 60);
  });

  test('photo: in-app capture through NF-004, upload + visit_photo op with '
      'taken_in_app, EXIF time / point and device time', () async {
    await goOnDuty();
    final id = await checkInInside();
    camera.enqueue(jpeg(textured(640, 480)));
    deps.clock.advance(const Duration(minutes: 2));
    final pending = await flow().capturePhoto();
    expect(pending, isNotNull);
    expect(camera.captures, 1);
    expect(pending!.processed.exif.takenAt, deps.clock.now);
    final photoId = await flow().acceptPhoto(id, pending);
    final op = (await visitOps()).last;
    expect('${op.entity}/${op.action}', 'visit_photo/create');
    expect(op.entityId, photoId);
    expect(op.dependsOnUploadId, isNotNull);
    final p = SyncStore.payloadOf(op);
    expect(p['visit_id'], id);
    expect(p['taken_in_app'], isTrue);
    expect(p['exif_time'], deps.clock.now.toIso8601String());
    expect((p['exif_point']! as Map)['lat'], closeTo(17.40045, 1e-4));
    expect(p['device_time'], deps.clock.now.toIso8601String());
    expect(p['sha256'], pending.processed.sha256);
    expect(p['blob_uri'], startsWith('upload:'));
    final upload = await SyncStore(deps.db).upload(op.dependsOnUploadId!);
    expect(upload!.purpose, 'visit_photo');
    // The live proof counts the photo.
    final detail = await c.read(visitRepositoryProvider).detail(id);
    expect(detail!.photos.single.localPath, isNotNull);
    expect(detail.proofAt(deps.clock.now).photoOk, isTrue);
  });

  test('capture + check-out ops; server-owned score replaces the local '
      'expectation on pull', () async {
    await goOnDuty();
    final id = await checkInInside();
    deps.clock.advance(const Duration(minutes: 3));
    expect(
      await flow().saveCapture(
        id,
        notes: ' Pest seen ',
        cropStage: 'flowering',
      ),
      isTrue,
    );
    expect(
      await flow().saveCapture(id, notes: 'Pest seen', cropStage: 'flowering'),
      isFalse,
    );
    deps.clock.advance(const Duration(minutes: 1));
    expect(await flow().checkOut(id), isTrue);
    expect(await flow().checkOut(id), isFalse);
    final ops = await visitOps();
    expect(ops.map((o) => '${o.entity}/${o.action}'), <String>[
      'visit/create',
      'visit/update',
      'visit/update',
    ]);
    expect(SyncStore.payloadOf(ops[1]), <String, Object?>{
      'notes': 'Pest seen',
      'crop_stage': 'flowering',
    });
    final checkout = SyncStore.payloadOf(ops[2]);
    expect(checkout['checkout_at'], deps.clock.now.toIso8601String());
    expect(checkout['checkout_point'], isNotNull);

    final repo = c.read(visitRepositoryProvider);
    var detail = (await repo.detail(id))!;
    expect(detail.open, isFalse);
    // Local expectation: 4 min < 5 min minimum, no photo, not confirmed.
    final local = detail.proofAt(deps.clock.now);
    expect(local.score, 40);
    expect(local.missing, <String>['confirmation', 'photo', 'duration']);
    expect(detail.serverScored, isFalse);

    // Sync, then the server's scored row arrives through the pull.
    await c.read(syncEngineProvider).syncNow();
    expect(
      deps.api.appliedOps
          .where((o) => o.entity == 'visit')
          .map((o) => o.action.name),
      <String>['create', 'update', 'update'],
    );
    deps.api.addChange(
      entity: 'visit',
      action: SyncAction.update,
      entityId: id,
      version: 5,
      data: <String, Object?>{
        ...deps.api.row('visit', id)!.data,
        'geofence_result': 'inside',
        'score': 70,
        'status': 'verified',
        'duration_s': 240,
        'flags': <String>['under_minimum'],
        'score_components': <String, int>{
          'geofence': 30,
          'confirmation': 30,
          'photo': 0,
          'duration': 0,
          'integrity': 10,
        },
        'confirmed_at': deps.clock.now.toIso8601String(),
      },
    );
    await c.read(syncEngineProvider).syncNow();
    detail = (await repo.detail(id))!;
    expect(detail.visit.score, 70);
    expect(detail.visit.status, 'verified');
    expect(detail.serverComponents!['confirmation'], 30);
    expect(detail.flags, <String>['under_minimum']);
    expect(detail.visit.version, 5);
    // Device-only fields survive the server row.
    expect(detail.visit.precheckResult, 'inside');
    expect(detail.visit.notes, 'Pest seen');
  });

  test('conflict with the server payload applies the score fields', () async {
    await goOnDuty();
    final id = await checkInInside();
    deps.api.script = (op) => op.entity == 'visit'
        ? SyncOpResult(
            opId: op.opId,
            status: SyncResultStatus.conflict,
            entityId: op.entityId,
            version: 3,
            server: <String, Object?>{
              ...op.payload,
              'geofence_result': 'inside',
              'score': 100,
              'status': 'verified',
              'checkout_at': dutyT0
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
              'score_components': const <String, int>{'geofence': 30},
            },
          )
        : null;
    await c.read(syncEngineProvider).syncNow();
    final row = (await c.read(visitRepositoryProvider).visit(id))!;
    expect(row.score, 100);
    expect(row.status, 'verified');
    expect(row.version, 3);
    expect(row.precheckResult, 'inside');
  });

  test('rejected outside_geofence: row marked failed with the distance; '
      'retry from the farm requeues with the new fix', () async {
    await goOnDuty();
    final id = await checkInInside();
    deps.api.validate = (op) =>
        op.entity == 'visit' && op.action == SyncAction.create
        ? const SyncError(
            'outside_geofence',
            '412 m from the farm boundary; the geofence is 150 m.',
            <String, Object?>{
              'distance_m': 412.4,
              'target': 'farm',
              'radius_m': 150,
            },
          )
        : null;
    final report = await c.read(syncEngineProvider).syncNow();
    expect(report.rejected, 1);
    final repo = c.read(visitRepositoryProvider);
    var detail = (await repo.detail(id))!;
    expect(detail.failure!.outsideGeofence, isTrue);
    expect(detail.failure!.distanceM, 412.4);
    expect(detail.failure!.target, 'farm');
    expect(await repo.openVisit(), isNull);

    // Still outside: nothing requeued.
    deps.sampler.initial = fixAt(dutyT0, east: 600, north: 50);
    var retry = await flow().retryFromFarm(id);
    expect(retry.result, RetryResult.stillOutside);
    expect(await repo.rejectedOp(id), isNotNull);

    // At the farm: requeued under the same op id with the new point.
    deps.api.validate = null;
    deps.clock.advance(const Duration(minutes: 10));
    deps.sampler.initial = fixAt(dutyT0, east: 20, north: 20);
    retry = await flow().retryFromFarm(id);
    expect(retry.result, RetryResult.retried);
    detail = (await repo.detail(id))!;
    expect(detail.failure, isNull);
    final op = (await visitOps()).single;
    expect(op.state, 'queued');
    expect(
      SyncStore.payloadOf(op)['checkin_at'],
      deps.clock.now.toIso8601String(),
    );
    expect((await c.read(syncEngineProvider).syncNow()).applied, 1);
  });

  test(
    'sync error parsing keeps problem extras and falls back to the detail',
    () {
      final e = SyncError.fromJson(<String, Object?>{
        'code': 'outside_geofence',
        'status': 422,
        'detail': '380 m from the meeting point; the geofence is 150 m.',
      })!;
      expect(e.distanceM, 380);
      final withExtra = SyncError.fromJson(<String, Object?>{
        'code': 'outside_geofence',
        'detail': 'x',
        'errors': <Object?>[
          <String, Object?>{
            'distance_m': 99.5,
            'target': 'farm',
            'radius_m': 150,
          },
        ],
      })!;
      expect(withExtra.distanceM, 99.5);
      expect(withExtra.target, 'farm');
      expect(withExtra.radiusM, 150);
    },
  );

  group('FA-016 confirmation', () {
    test(
      'OTP online: wrong code keeps it unconfirmed, right code confirms',
      () async {
        await goOnDuty();
        final id = await checkInInside();
        final req = await flow().requestConfirmation(
          id,
          ConfirmationChannel.smsOtp,
        );
        expect(req.result, RequestResult.ok);
        expect(req.api!.phoneMasked, '+91••••••3210');
        final repo = c.read(visitRepositoryProvider);
        expect((await repo.detail(id))!.latestConfirmation!.status, 'pending');

        final wrong = await flow().confirmOtp(id, '000000');
        expect(wrong.result, OtpConfirmResult.invalid);
        expect(wrong.attemptsLeft, 4);
        expect((await repo.detail(id))!.confirmed, isFalse);

        final ok = await flow().confirmOtp(id, '123456');
        expect(ok.result, OtpConfirmResult.ok);
        final detail = (await repo.detail(id))!;
        expect(detail.confirmed, isTrue);
        expect(detail.visit.confirmationChannel, 'sms_otp');
        expect(detail.latestConfirmation!.status, 'confirmed');
        expect(detail.proofAt(deps.clock.now).confirmed, isTrue);
      },
    );

    test('OTP and QR offline need the network; nothing is requested', () async {
      await goOnDuty();
      final id = await checkInInside();
      connectivity.online = false;
      expect(
        (await flow().requestConfirmation(
          id,
          ConfirmationChannel.smsOtp,
        )).result,
        RequestResult.needsNetwork,
      );
      expect(
        (await flow().requestConfirmation(id, ConfirmationChannel.qr)).result,
        RequestResult.needsNetwork,
      );
      expect(confirmApi.requests, isEmpty);
    });

    test(
      'push: queued offline, sent on reconnect, confirmed via pull',
      () async {
        await goOnDuty();
        final id = await checkInInside();
        connectivity.online = false;
        final req = await flow().requestConfirmation(
          id,
          ConfirmationChannel.appPush,
        );
        expect(req.result, RequestResult.queuedOffline);
        final repo = c.read(visitRepositoryProvider);
        expect((await repo.detail(id))!.latestConfirmation!.status, 'queued');
        expect(await flow().flushQueuedConfirmations(), 0);

        connectivity.online = true;
        await c.read(syncEngineProvider).syncNow();
        expect(await flow().flushQueuedConfirmations(), 1);
        expect(confirmApi.requests.single, (id, ConfirmationChannel.appPush));
        var detail = (await repo.detail(id))!;
        expect(detail.confirmations, hasLength(1));
        expect(detail.latestConfirmation!.status, 'pending');
        expect(detail.confirmed, isFalse);

        // The farmer taps Confirm; the pull brings confirmed_at.
        final confId = confirmApi.confirmationIds[id]!;
        deps.api
          ..addChange(
            entity: 'visit_confirmation',
            action: SyncAction.update,
            entityId: confId,
            version: 2,
            data: <String, Object?>{
              'id': confId,
              'visit_id': id,
              'channel': 'app_push',
              'status': 'confirmed',
              'confirmed_at': deps.clock.now.toIso8601String(),
            },
          )
          ..addChange(
            entity: 'visit',
            action: SyncAction.update,
            entityId: id,
            version: 2,
            data: <String, Object?>{
              ...deps.api.row('visit', id)!.data,
              'confirmation_channel': 'app_push',
              'confirmed_at': deps.clock.now.toIso8601String(),
            },
          );
        await c.read(syncEngineProvider).syncNow();
        detail = (await repo.detail(id))!;
        expect(detail.confirmed, isTrue);
        expect(detail.visit.confirmationChannel, 'app_push');
        expect(detail.latestConfirmation!.status, 'confirmed');
      },
    );

    test(
      'QR: the request token is kept on the device and never pushed',
      () async {
        await goOnDuty();
        final id = await checkInInside();
        final req = await flow().requestConfirmation(
          id,
          ConfirmationChannel.qr,
        );
        expect(req.result, RequestResult.ok);
        final conf = (await c.read(visitRepositoryProvider).detail(id))!
            .latestConfirmation!;
        expect(conf.token, FakeVisitConfirmApi.tokenFor(id));
        expect(conf.channel, 'qr');
        expect(
          (await visitOps()).where((o) => o.entity == 'visit_confirmation'),
          isEmpty,
        );
        expect(jsonEncode(await outboxRows(deps.db)), isNot(contains('token')));
      },
    );

    test('check-in not synced yet answers notSynced', () async {
      await goOnDuty();
      final id = await checkInInside();
      confirmApi.unknownVisits.add(id);
      expect(
        (await flow().requestConfirmation(id, ConfirmationChannel.qr)).result,
        RequestResult.notSynced,
      );
    });
  });

  test(
    'no photo bytes: a cancelled camera gives null and queues nothing',
    () async {
      await goOnDuty();
      await checkInInside();
      expect(await flow().capturePhoto(), isNull);
      expect((await visitOps()).length, 1);
    },
  );
}
