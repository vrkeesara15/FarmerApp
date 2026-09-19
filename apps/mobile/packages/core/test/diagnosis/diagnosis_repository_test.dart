// FM-004 .. FM-006 / FA-019 data layer: photos + resumable uploads + the
// `diagnosis` create op (offline first), the answer from the applied echo,
// the poll and the change feed, F27 history, "ask an expert", and the SPEC
// 3.4 buy rule on the model.
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../photo/synthetic_images.dart';
import '../sync/sync_harness.dart';

CapturedPhoto _photo({int seed = 3, PhotoQualityResult? quality}) {
  final processed = processPhotoSync(
    PhotoProcessRequest(bytes: jpeg(textured(640, 480, seed: seed))),
  );
  return CapturedPhoto(
    processed: processed,
    quality:
        quality ??
        const PhotoQualityResult(
          isBlurry: false,
          blurScore: 0.02,
          isTooDark: false,
          brightness: 0.46,
          tipKey: PhotoTipKeys.ok,
          plantScore: 0.99,
          cropCode: 'chilli',
          cropScore: 0.93,
          modelVersion: 'ondevice-v1.0',
        ),
  );
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late FakeSyncApi sync;
  late FakeDiagnosisApi api;
  late FakeDiagnosisServer server;
  late MemoryPhotoStore photos;
  late DiagnosisRepository repo;
  late SyncEngine engine;
  var n = 0;

  setUp(() {
    db = newDb();
    clock = FakeClock(t0);
    sync = FakeSyncApi();
    api = FakeDiagnosisApi();
    server = FakeDiagnosisServer(sync: sync, api: api, clock: clock.call);
    photos = MemoryPhotoStore();
    n = 0;
    final outbox = Outbox(db, clock: clock.call, ids: () => 'op-${++n}');
    repo = DiagnosisRepository(
      db: db,
      outbox: outbox,
      photos: photos,
      api: api,
      clock: clock.call,
      ids: () => 'dx-${++n}',
    );
    engine = engineFor(
      db,
      sync,
      clock: clock,
      readFile: (path) async => photos.files[path]!,
    );
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  test('submit saves photos, queues uploads and one create op', () async {
    final id = await repo.submit(
      DiagnosisRequest(
        photos: <CapturedPhoto>[_photo(), _photo(seed: 4)],
        cropId: 'pilot:chilli',
        cropCode: 'chilli',
        onDeviceModel: 'ondevice-v1.0',
      ),
    );
    expect(photos.files, hasLength(2));
    final ops = await engine.store.openOps();
    expect(ops, hasLength(1));
    final op = SyncStore.toOp(ops.single);
    expect(op.entity, SyncEntities.diagnosis);
    expect(op.entityId, id);
    expect(op.payload.containsKey('id'), isFalse, reason: 'contract');
    expect(op.payload['crop_id'], 'unknown', reason: 'pilot placeholder');
    expect(op.payload.containsKey('crop_guess'), isFalse, reason: 'flag off');
    expect(op.payload['on_device_model'], 'ondevice-v1.0');
    expect(op.payload['ask_expert'], isFalse);
    final images = op.payload['images']! as List;
    expect(images, hasLength(2));
    final first = images.first as Map;
    expect('${first['blob_uri']}', startsWith(uploadPlaceholderPrefix));
    expect(
      (first['quality'] as Map).keys,
      unorderedEquals(<String>[
        'passed',
        'blur_score',
        'brightness',
        'plant_present',
      ]),
    );
    final d = (await repo.get(id))!;
    expect(d.status, DiagnosisStatus.pending);
    expect(d.waitingForNetwork, isTrue);
    expect(d.localPhotos, hasLength(2));
    expect(d.cropCode, 'chilli');
  });

  test('a server crop id and the crop guess are sent when given', () async {
    await repo.submit(
      DiagnosisRequest(
        photos: <CapturedPhoto>[_photo()],
        farmerId: 'farmer-9',
        cropPlotId: 'plot-9',
        cropId: '5f0c7a8e-1d2b-4c3d-9e4f-0a1b2c3d4e5f',
        cropGuess: ('chilli', 0.93),
        subject: 'officer',
      ),
    );
    final op = SyncStore.toOp((await engine.store.openOps()).single);
    expect(op.payload['crop_id'], '5f0c7a8e-1d2b-4c3d-9e4f-0a1b2c3d4e5f');
    expect(op.payload['farmer_id'], 'farmer-9');
    expect(op.payload['crop_plot_id'], 'plot-9');
    expect(op.payload['crop_guess'], <String, Object?>{
      'code': 'chilli',
      'confidence': 0.93,
    });
  });

  test('rejected photos are never submitted', () async {
    final blurry = _photo(
      quality: const PhotoQualityResult(
        isBlurry: true,
        blurScore: 0.9,
        isTooDark: false,
        brightness: 0.4,
        tipKey: PhotoTipKeys.blurry,
      ),
    );
    expect(
      () => repo.submit(DiagnosisRequest(photos: <CapturedPhoto>[blurry])),
      throwsArgumentError,
    );
  });

  test('offline: queued; online: uploads, create op, answer applied', () async {
    final id = await repo.submit(
      DiagnosisRequest(photos: <CapturedPhoto>[_photo()]),
    );
    sync.offline = true;
    final failed = await engine.syncNow();
    expect(failed.error, isNotNull);
    expect((await repo.get(id))!.status, DiagnosisStatus.pending);

    sync.offline = false;
    await engine.syncNow();
    expect(server.creates, hasLength(1));
    final sent = server.creates.single.payload['images']! as List;
    expect(
      '${(sent.single as Map)['blob_uri']}',
      allOf(startsWith('blob://'), isNot(startsWith(uploadPlaceholderPrefix))),
    );
    final d = (await repo.get(id))!;
    expect(d.status, DiagnosisStatus.answered);
    expect(d.waitingForNetwork, isFalse);
    expect(d.problem!.code, 'chilli_anthracnose');
    expect(d.confidence, ConfidenceLevel.high);
    expect(d.canBuy, isTrue);
    expect(d.showBuy, isTrue);
    expect(d.chemical.first.labelClaimId, 'lc-azoxy');
    expect(d.localPhotos, hasLength(1), reason: '_local kept over the echo');
  });

  test('queued on the server: the poll picks the answer up', () async {
    server.next = FakeDiagnosisOutcome.queued;
    final id = await repo.submit(
      DiagnosisRequest(photos: <CapturedPhoto>[_photo()]),
    );
    await engine.syncNow();
    expect((await repo.get(id))!.status, DiagnosisStatus.queued);
    final sleeps = <Duration>[];
    final poller = DiagnosisPoller(
      repository: repo,
      sleep: (d) async {
        sleeps.add(d);
        if (sleeps.length == 2) server.answer(id, FakeDiagnosisOutcome.high);
      },
    );
    final d = await poller.run(id);
    expect(d!.status, DiagnosisStatus.answered);
    expect(sleeps, <Duration>[
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
    expect(DiagnosisPoller.delayFor(10), const Duration(seconds: 10));
  });

  test('provisional: no buy even if the server said can_buy', () {
    final out = FakeDiagnosisServer.diagnosisOut(
      id: 'x',
      outcome: FakeDiagnosisOutcome.provisional,
    )..['can_buy'] = true;
    final d = Diagnosis.fromData('x', out);
    expect(d.provisional, isTrue);
    expect(d.showBuy, isFalse);
    expect(d.cta, 'talk_to_field_officer');
  });

  test('out of scope carries the reason and no products', () {
    final d = Diagnosis.fromData(
      'x',
      FakeDiagnosisServer.diagnosisOut(
        id: 'x',
        outcome: FakeDiagnosisOutcome.notAPlant,
      ),
    );
    expect(d.isOutOfScope, isTrue);
    expect(d.outOfScopeReason, 'not_a_plant');
    expect(d.options, isEmpty);
    expect(d.showBuy, isFalse);
  });

  test('F27: an agronomist review via the feed keeps the earlier answer '
      'and raises the banner until seen', () async {
    server.next = FakeDiagnosisOutcome.provisional;
    final id = await repo.submit(
      DiagnosisRequest(photos: <CapturedPhoto>[_photo()]),
    );
    await engine.syncNow();
    expect((await repo.get(id))!.showBuy, isFalse);

    server.review(id, corrected: true);
    await engine.syncNow();
    var d = (await repo.get(id))!;
    expect(d.status, DiagnosisStatus.corrected);
    expect(d.showBuy, isTrue);
    expect(d.problem!.code, 'chilli_leaf_curl');
    expect(d.updateUnseen, isTrue);
    expect(d.history, hasLength(1));
    expect(d.history.single.status, DiagnosisStatus.provisional);
    expect(d.history.single.nameIn('en'), 'Anthracnose (fruit rot)');

    await repo.markSeen(id);
    d = (await repo.get(id))!;
    expect(d.updateUnseen, isFalse);
    expect(d.history, hasLength(1));
  });

  test('the first answer is not an "update"', () async {
    server.next = FakeDiagnosisOutcome.queued;
    final id = await repo.submit(
      DiagnosisRequest(photos: <CapturedPhoto>[_photo()]),
    );
    await engine.syncNow();
    server.answer(id, FakeDiagnosisOutcome.high);
    await engine.syncNow();
    final d = (await repo.get(id))!;
    expect(d.status, DiagnosisStatus.answered);
    expect(d.history, isEmpty);
    expect(d.updateUnseen, isFalse);
  });

  group('ask an expert (FM-006)', () {
    test('provisional / out of scope: already with the expert', () async {
      server.next = FakeDiagnosisOutcome.provisional;
      final id = await repo.submit(
        DiagnosisRequest(photos: <CapturedPhoto>[_photo()]),
      );
      await engine.syncNow();
      final (outcome, _) = await repo.askExpert(id);
      expect(outcome, AskExpertOutcome.alreadyWithExpert);
      expect(await engine.store.openOps(), isEmpty);
    });

    test('still queued: the flag is added to the queued request', () async {
      final id = await repo.submit(
        DiagnosisRequest(photos: <CapturedPhoto>[_photo()]),
      );
      final (outcome, same) = await repo.askExpert(id);
      expect(outcome, AskExpertOutcome.addedToQueued);
      expect(same, id);
      final op = SyncStore.toOp((await engine.store.openOps()).single);
      expect(op.payload['ask_expert'], isTrue);
      await engine.syncNow();
      expect(server.creates.single.payload['ask_expert'], isTrue);
    });

    test('answered: the same photos go to the expert as a new case', () async {
      final id = await repo.submit(
        DiagnosisRequest(photos: <CapturedPhoto>[_photo()]),
      );
      await engine.syncNow();
      final (outcome, newId) = await repo.askExpert(id);
      expect(outcome, AskExpertOutcome.sent);
      expect(newId, isNot(id));
      await engine.syncNow();
      final second = server.creates.last.payload;
      expect(second['ask_expert'], isTrue);
      expect(
        (second['images']! as List).single,
        containsPair('blob_uri', startsWith('blob://')),
      );
    });
  });

  test('watchAll filters by farmer and plot (A22 Diagnoses tab)', () async {
    await repo.submit(
      DiagnosisRequest(
        photos: <CapturedPhoto>[_photo()],
        farmerId: 'farmer-a',
        cropPlotId: 'plot-a',
        subject: 'officer',
      ),
    );
    await repo.submit(
      DiagnosisRequest(
        photos: <CapturedPhoto>[_photo()],
        farmerId: 'farmer-b',
        subject: 'officer',
      ),
    );
    final a = await repo.watchAll(farmerId: 'farmer-a').first;
    expect(a, hasLength(1));
    expect(a.single.cropPlotId, 'plot-a');
    expect(a.single.subject, 'officer');
    expect(await repo.watchAll(cropPlotId: 'plot-a').first, hasLength(1));
    expect(await repo.watchAll().first, hasLength(2));
  });

  test('a refused create is kept with its code for the retry screen', () async {
    sync.validate = (op) => op.entity == SyncEntities.diagnosis
        ? const SyncError('diagnosis_image_missing')
        : null;
    // The fake server script answers creates itself; drop it for this test.
    sync.script = null;
    final id = await repo.submit(
      DiagnosisRequest(photos: <CapturedPhoto>[_photo()]),
    );
    await engine.syncNow();
    final d = (await repo.get(id))!;
    expect(d.failureCode, 'diagnosis_image_missing');
    expect(d.status, DiagnosisStatus.pending);
  });
}
