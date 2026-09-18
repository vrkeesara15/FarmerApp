import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../photo/synthetic_images.dart';
import 'farmers_harness.dart';

/// FA-012 / FA-013 wizard state: draft persistence and resume, per-step
/// validation, local duplicate block, OTP online and "verify later"
/// offline, boundary capture with the VA-F03 area warning, photos through
/// the NF-004 pipeline, and the save that queues everything in order.
void main() {
  late WizardDeps deps;
  late ProviderContainer container;
  late RegistrationNotifier wizard;

  RegistrationDraft draft() => container.read(registrationProvider).draft!;
  RegistrationState st() => container.read(registrationProvider);

  setUp(() async {
    deps = WizardDeps();
    await seedVillage(deps.db);
    container = deps.container();
    wizard = container.read(registrationProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await deps.dispose();
  });

  /// Fills A21a so the basics step passes (verified via OTP).
  Future<void> fillBasics({String phone = '9876543210'}) async {
    await wizard.setName('Ramesh Reddy');
    await wizard.setPhone(phone);
    await wizard.setVillage('village-1', name: 'Kondapur');
    await wizard.setLandmark('Near the temple');
    await wizard.setLanguage('te');
    await wizard.setLandOwnership(LandOwnershipTypes.own);
    await wizard.sendOtp();
    await wizard.confirmOtp('123456');
  }

  /// Fills A21b + A21c for the current farm.
  Future<void> fillFarm({
    required List<GeoPoint> ring,
    required double acres,
    required List<(String crop, DateTime sown)> plots,
  }) async {
    await wizard.setBoundaryMode(BoundaryMode.tap);
    for (final p in ring) {
      await wizard.addCorner(p);
    }
    await wizard.setDeclaredAcres(acres);
    await wizard.setSoil('black');
    await wizard.setIrrigation('borewell');
    for (final (crop, sown) in plots) {
      await wizard.addPlot();
      final plot = draft().farm!.plots.last;
      await wizard.updatePlot(
        plot.id,
        cropId: crop,
        variety: 'Bt',
        sowingDate: sown,
      );
    }
  }

  group('draft persistence', () {
    test('start creates a fresh draft with one farm and stores it', () async {
      await wizard.start(language: 'te');
      final d = draft();
      expect(st().restored, isTrue);
      expect(d.mode, DraftMode.newFarmer);
      expect(d.farms, hasLength(1));
      expect(d.language, 'te');
      expect(d.step, 0);
      final stored = await deps.db.getValue(RegistrationDraft.kvKey);
      expect(stored, isNotNull);
      expect(
        (jsonDecode(stored!) as Map<String, Object?>)['farmer_id'],
        d.farmerId,
      );
    });

    test(
      'an interrupted wizard resumes at the same step with its data',
      () async {
        await wizard.start();
        await fillBasics();
        expect(await wizard.next(), isEmpty);
        await wizard.addCorner(farmOrigin);
        await wizard.setDeclaredAcres(2.5);
        final farmerId = draft().farmerId;

        // "App killed": a new container over the same database.
        container.dispose();
        container = deps.container();
        wizard = container.read(registrationProvider.notifier);
        expect(st().draft, isNull);
        await wizard.start();
        final d = draft();
        expect(d.farmerId, farmerId);
        expect(d.step, 1);
        expect(wizard.currentStep, RegistrationStep.boundary);
        expect(d.name, 'Ramesh Reddy');
        expect(d.phone, '9876543210');
        expect(d.verification, PhoneVerification.verified);
        expect(d.verificationToken, 'pv-token-1');
        expect(d.farm!.boundary, <GeoPoint>[farmOrigin]);
        expect(d.farm!.declaredAcres, 2.5);
      },
    );

    test('discard clears the stored draft', () async {
      await wizard.start();
      await wizard.setName('X');
      await wizard.discard();
      expect(await deps.db.getValue(RegistrationDraft.kvKey), isNull);
      expect(st().draft, isNull);
    });

    test('a farm-mode draft for another farmer is not resumed', () async {
      await wizard.start(mode: DraftMode.farm, farmerId: 'f-a');
      await wizard.addCorner(farmOrigin);
      await wizard.start(mode: DraftMode.farm, farmerId: 'f-b');
      expect(draft().farmerId, 'f-b');
      expect(draft().farm!.boundary, isEmpty);
      // ... and a new-farmer wizard never picks up a farm draft.
      await wizard.start();
      expect(draft().mode, DraftMode.newFarmer);
    });
  });

  group('A21a validation', () {
    test('empty basics report every missing field', () async {
      await wizard.start();
      expect(
        wizard.issuesFor(RegistrationStep.basics),
        containsAll(<StepIssue>[
          StepIssue.nameRequired,
          StepIssue.phoneInvalid,
          StepIssue.phoneUnverified,
          StepIssue.villageRequired,
          StepIssue.languageRequired,
        ]),
      );
      expect(await wizard.next(), isNotEmpty);
      expect(draft().step, 0);
    });

    test('a typed village stands in when none have synced', () async {
      await wizard.start();
      await wizard.setVillageName('Nallagutta');
      expect(
        wizard.issuesFor(RegistrationStep.basics),
        isNot(contains(StepIssue.villageRequired)),
      );
      expect(draft().villageId, isNull);
    });

    test('an invalid number blocks and is not sent', () async {
      await wizard.start();
      await wizard.setPhone('12345');
      await wizard.sendOtp();
      expect(st().otpFailure, OtpFailure.invalidNumber);
      expect(deps.verify.sent, isEmpty);
    });

    test('local duplicate phone is blocked immediately', () async {
      await seedSyncedFarmer(deps.db, id: 'f-existing', phone: '+919876543210');
      await wizard.start();
      await wizard.setName('Ramesh');
      await wizard.setPhone('9876543210');
      expect(st().duplicateOfId, 'f-existing');
      expect(
        wizard.issuesFor(RegistrationStep.basics),
        contains(StepIssue.phoneDuplicate),
      );
      await wizard.setPhone('9876543211');
      expect(st().duplicateOfId, isNull);
      expect(
        wizard.issuesFor(RegistrationStep.basics),
        isNot(contains(StepIssue.phoneDuplicate)),
      );
    });

    test('a tombstoned farmer does not count as a duplicate', () async {
      await seedSyncedFarmer(deps.db, id: 'f-gone', phone: '+919876543210');
      await LocalEntities(deps.db)
          .setFlags(SyncEntities.farmer, 'f-gone', now: t0, deleted: true);
      await wizard.start();
      await wizard.setPhone('9876543210');
      expect(st().duplicateOfId, isNull);
    });
  });

  group('OTP', () {
    test(
      'online: send, wrong code, right code -> verified with token',
      () async {
        await wizard.start();
        await wizard.setPhone('9876543210');
        await wizard.sendOtp();
        expect(deps.verify.sent, <String>['+919876543210']);
        expect(draft().verification, PhoneVerification.sent);
        expect(st().otpRetryAfter, const Duration(seconds: 30));

        await wizard.confirmOtp('000000');
        expect(st().otpFailure, OtpFailure.wrongCode);
        expect(st().otpAttemptsLeft, 4);
        expect(draft().verification, PhoneVerification.sent);

        await wizard.confirmOtp('123456');
        expect(st().otpFailure, OtpFailure.none);
        expect(draft().verification, PhoneVerification.verified);
        expect(draft().verificationToken, 'pv-token-1');
        expect(
          draft().verificationExpiresAt,
          t0.add(const Duration(minutes: 30)),
        );
        expect(
          draft().isVerifiedAt(t0.add(const Duration(minutes: 29))),
          isTrue,
        );
        expect(
          draft().isVerifiedAt(t0.add(const Duration(minutes: 31))),
          isFalse,
        );
      },
    );

    test('five wrong codes lock the number', () async {
      await wizard.start();
      await wizard.setPhone('9876543210');
      await wizard.sendOtp();
      for (var i = 0; i < 5; i++) {
        await wizard.confirmOtp('00000$i');
      }
      expect(st().otpFailure, OtpFailure.locked);
      expect(st().otpRetryAfter, const Duration(minutes: 15));
    });

    test('changing the number resets verification', () async {
      await wizard.start();
      await wizard.setPhone('9876543210');
      await wizard.sendOtp();
      await wizard.confirmOtp('123456');
      await wizard.setPhone('9876543211');
      expect(draft().verification, PhoneVerification.unverified);
      expect(draft().verificationToken, isNull);
    });

    test(
      'offline: send fails with network and verify later unblocks',
      () async {
        deps.connectivity.online = false;
        await wizard.start();
        await wizard.setName('Ramesh');
        await wizard.setPhone('9876543210');
        await wizard.setVillage('village-1');
        await wizard.setLanguage('te');
        await wizard.sendOtp();
        expect(st().otpFailure, OtpFailure.network);
        expect(deps.verify.sent, isEmpty);
        expect(
          wizard.issuesFor(RegistrationStep.basics),
          contains(StepIssue.phoneUnverified),
        );

        await wizard.verifyLater();
        expect(draft().verification, PhoneVerification.verifyLater);
        expect(wizard.issuesFor(RegistrationStep.basics), isEmpty);
        final payload = wizard.farmerPayload();
        expect(payload['phone_verified'], isFalse);
        expect(payload.containsKey(phoneVerificationTokenKey), isFalse);
        expect(await wizard.next(), isEmpty);
        expect(wizard.currentStep, RegistrationStep.boundary);
      },
    );
  });

  group('A21b boundary', () {
    test('walk-around appends spaced fixes, close stops the GPS', () async {
      await wizard.start();
      await wizard.goTo(RegistrationStep.boundary);
      await wizard.startWalk();
      expect(st().walking, isTrue);
      expect(st().location, LocationAvailability.available);
      expect(deps.location.listeners, 1);

      deps.location.emit(fixAt(farmOrigin, accuracy: 12));
      deps.location.emit(fixAt(offsetPoint(1, 0))); // < 3 m: ignored
      deps.location.emit(fixAt(offsetPoint(100, 0)));
      deps.location.emit(fixAt(offsetPoint(100, 100)));
      deps.location.emit(fixAt(offsetPoint(0, 100), accuracy: 4));
      await Future<void>.delayed(Duration.zero);
      expect(draft().farm!.boundary, hasLength(4));
      expect(draft().farm!.mode, BoundaryMode.walk);
      expect(st().lastFix!.accuracyMetres, 4);
      expect(draft().farm!.computedAcres, closeTo(2.47, 0.02));

      await wizard.closePolygon();
      expect(draft().farm!.closed, isTrue);
      expect(st().walking, isFalse);
      expect(deps.location.listeners, 0);
      // Fixes after closing are not appended.
      deps.location.emit(fixAt(offsetPoint(50, 50)));
      await Future<void>.delayed(Duration.zero);
      expect(draft().farm!.boundary, hasLength(4));
    });

    test('location off or denied does not start a walk', () async {
      await wizard.start();
      deps.location.availability = LocationAvailability.permissionDenied;
      await wizard.startWalk();
      expect(st().walking, isFalse);
      expect(st().location, LocationAvailability.permissionDenied);
      expect(deps.location.listeners, 0);
    });

    test('tap mode: corners, undo, clear', () async {
      await wizard.start();
      for (final p in squareHectare) {
        await wizard.addCorner(p);
      }
      expect(draft().farm!.mode, BoundaryMode.tap);
      expect(draft().farm!.closed, isTrue);
      expect(draft().farm!.hasPolygon, isTrue);
      await wizard.undoPoint();
      expect(draft().farm!.boundary, hasLength(3));
      await wizard.clearBoundary();
      expect(draft().farm!.boundary, isEmpty);
      expect(
        wizard.issuesFor(RegistrationStep.boundary),
        contains(StepIssue.boundaryTooFewPoints),
      );
    });

    test(
      'VA-F03: area warning beyond 30 percent, self-intersection blocks',
      () async {
        await wizard.start();
        await wizard.goTo(RegistrationStep.boundary);
        for (final p in squareHectare) {
          await wizard.addCorner(p);
        }
        await wizard.setDeclaredAcres(10);
        expect(draft().farm!.areaMismatch, isTrue);
        // A warning, not a block: the step still passes.
        expect(wizard.issuesFor(RegistrationStep.boundary), isEmpty);
        await wizard.setDeclaredAcres(2.5);
        expect(draft().farm!.areaMismatch, isFalse);
        await wizard.useComputedAcres();
        expect(draft().farm!.declaredAcres, closeTo(2.47, 0.01));

        await wizard.clearBoundary();
        final bowTie = <GeoPoint>[
          farmOrigin,
          offsetPoint(100, 100),
          offsetPoint(100, 0),
          offsetPoint(0, 100),
        ];
        for (final p in bowTie) {
          await wizard.addCorner(p);
        }
        expect(
          wizard.issuesFor(RegistrationStep.boundary),
          contains(StepIssue.boundarySelfIntersecting),
        );
        expect(
          await wizard.next(),
          contains(StepIssue.boundarySelfIntersecting),
        );
      },
    );

    test('farm photo: camera -> NF-004 pipeline -> queued upload', () async {
      deps.camera.enqueue(jpeg(textured(1600, 1200)));
      await wizard.start();
      await wizard.takePhoto();
      final pending = st().pendingPhoto;
      expect(pending, isNotNull);
      expect(pending!.processed.width, 1280);
      expect(pending.quality.isAcceptable, isTrue);
      expect(draft().farm!.photos, isEmpty);

      await wizard.usePhoto();
      expect(st().pendingPhoto, isNull);
      final photo = draft().farm!.photos.single;
      expect(photo.width, 1280);
      expect(deps.photos.files.containsKey(photo.filePath), isTrue);
      final upload = await deps.db.select(deps.db.uploads).getSingle();
      expect(upload.id, photo.uploadId);
      expect(upload.purpose, 'farm_photo');
      expect(upload.state, 'pending');
      expect(wizard.farmPayload(draft().farm!)['photos'], <String>[
        'upload:${photo.uploadId}',
      ]);

      await wizard.removePhoto(photo.uploadId);
      expect(draft().farm!.photos, isEmpty);
    });

    test('a cancelled camera leaves nothing pending', () async {
      await wizard.start();
      await wizard.takePhoto();
      expect(st().pendingPhoto, isNull);
      expect(st().photoBusy, isFalse);
      expect(deps.camera.captures, 1);
    });
  });

  group('A21c crops', () {
    test(
      'plots need a crop and a sowing date; season follows the date',
      () async {
        await wizard.start();
        await wizard.goTo(RegistrationStep.crops);
        expect(
          wizard.issuesFor(RegistrationStep.crops),
          contains(StepIssue.cropRequired),
        );
        await wizard.addPlot();
        final id = draft().farm!.plots.single.id;
        expect(
          wizard.issuesFor(RegistrationStep.crops),
          containsAll(<StepIssue>[
            StepIssue.cropRequired,
            StepIssue.sowingDateRequired,
          ]),
        );
        await wizard.updatePlot(id, cropId: 'pilot:cotton');
        await wizard.updatePlot(id, sowingDate: DateTime(2026, 6, 15));
        expect(wizard.issuesFor(RegistrationStep.crops), isEmpty);
        expect(draft().farm!.plots.single.season, Seasons.kharif);
        await wizard.updatePlot(id, sowingDate: DateTime(2026, 11, 2));
        expect(draft().farm!.plots.single.season, Seasons.rabi);
        await wizard.updatePlot(id, sowingDate: DateTime(2026, 4, 2));
        expect(draft().farm!.plots.single.season, Seasons.zaid);
        await wizard.removePlot(id);
        expect(draft().farm!.plots, isEmpty);
      },
    );
  });

  group('A21d consent', () {
    test('data consent is required, marketing is optional', () async {
      await wizard.start();
      expect(wizard.issuesFor(RegistrationStep.consent), <StepIssue>[
        StepIssue.consentRequired,
      ]);
      await wizard.setConsentData(granted: true);
      expect(wizard.issuesFor(RegistrationStep.consent), isEmpty);
      expect(draft().consentMarketing, isFalse);
    });
  });

  group('save (FA-012 + FA-013)', () {
    test(
      '2 farms and 3 plots queue the ops in order; sync applies all',
      () async {
        await wizard.start();
        await fillBasics();
        await wizard.next();
        await fillFarm(
          ring: squareHectare,
          acres: 2.5,
          plots: <(String, DateTime)>[('pilot:cotton', DateTime(2026, 6, 15))],
        );
        await wizard.setFarmName('Home farm');
        await wizard.next();
        expect(wizard.currentStep, RegistrationStep.crops);
        await wizard.next();
        expect(wizard.currentStep, RegistrationStep.consent);

        await wizard.addFarm();
        expect(draft().farms, hasLength(2));
        expect(wizard.currentStep, RegistrationStep.boundary);
        await fillFarm(
          ring: <GeoPoint>[
            offsetPoint(300, 0),
            offsetPoint(500, 0),
            offsetPoint(500, 200),
            offsetPoint(300, 200),
          ],
          acres: 10,
          plots: <(String, DateTime)>[
            ('pilot:paddy', DateTime(2026, 7, 2)),
            ('pilot:chilli', DateTime(2026, 7, 10)),
          ],
        );
        await wizard.next();
        await wizard.next();
        await wizard.setConsentData(granted: true);
        await wizard.setConsentMarketing(granted: true);
        await wizard.next();
        expect(wizard.currentStep, RegistrationStep.review);
        expect(wizard.issuesFor(RegistrationStep.review), isEmpty);

        expect(await wizard.save(), isEmpty);
        final farmerId = st().savedFarmerId!;
        expect(farmerId, draft().farmerId);
        expect(await deps.db.getValue(RegistrationDraft.kvKey), isNull);

        final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
        expect(ops.map((o) => '${o.entity}:${o.action}'), <String>[
          'farmer:create',
          'farm:create',
          'crop_plot:create',
          'farm:create',
          'crop_plot:create',
          'crop_plot:create',
          'consent_record:create',
          'consent_record:create',
        ]);
        expect(ops.map((o) => o.seq), <int>[1, 2, 3, 4, 5, 6, 7, 8]);

        final farmer = SyncStore.payloadOf(ops[0]);
        expect(farmer['id'], farmerId);
        expect(farmer['phone'], '+919876543210');
        expect(farmer['name'], 'Ramesh Reddy');
        expect(farmer['village_id'], 'village-1');
        expect(farmer['landmark'], 'Near the temple');
        expect(farmer['language'], 'te');
        expect(farmer['land_ownership'], 'own');
        expect(farmer['source'], 'field_officer');
        expect(farmer['phone_verified'], isTrue);
        expect(farmer['consent_marketing'], isTrue);
        expect(farmer[phoneVerificationTokenKey], 'pv-token-1');

        final farm1 = SyncStore.payloadOf(ops[1]);
        expect(farm1['farmer_id'], farmerId);
        expect(farm1['name'], 'Home farm');
        expect(farm1['area_acres'], 2.5);
        expect(farm1['soil'], 'black');
        expect(farm1['irrigation'], 'borewell');
        expect(farm1['ownership'], 'own');
        expect((farm1['boundary']! as Map)['type'], 'Polygon');
        final ring =
            ((farm1['boundary']! as Map)['coordinates']! as List).first as List;
        expect(ring, hasLength(5));
        expect(ring.first, ring.last);
        expect(farm1['photos'], isEmpty);

        final plot1 = SyncStore.payloadOf(ops[2]);
        expect(plot1['farm_id'], farm1['id']);
        expect(plot1['crop_id'], 'pilot:cotton');
        expect(plot1['variety'], 'Bt');
        expect(plot1['season'], 'kharif');
        expect(plot1['sowing_date'], '2026-06-15');

        final farm2 = SyncStore.payloadOf(ops[3]);
        expect(farm2['area_acres'], 10);
        expect(SyncStore.payloadOf(ops[4])['farm_id'], farm2['id']);
        expect(SyncStore.payloadOf(ops[5])['farm_id'], farm2['id']);
        expect(SyncStore.payloadOf(ops[5])['crop_id'], 'pilot:chilli');

        final consentData = SyncStore.payloadOf(ops[6]);
        expect(consentData['farmer_id'], farmerId);
        expect(consentData['purpose'], 'data');
        expect(consentData['granted'], isTrue);
        expect(consentData['language'], 'te');
        final consentMarketing = SyncStore.payloadOf(ops[7]);
        expect(consentMarketing['purpose'], 'marketing');
        expect(consentMarketing['granted'], isTrue);

        // Local rows exist, dirty, version 0 (offline).
        final farms = await deps.db.select(deps.db.farms).get();
        expect(farms, hasLength(2));
        expect(farms.every((f) => f.dirty && f.version == 0), isTrue);
        expect(await deps.db.select(deps.db.cropPlots).get(), hasLength(3));
        expect(
          await deps.db.select(deps.db.consentRecords).get(),
          hasLength(2),
        );
        final local = await deps.db.select(deps.db.farmers).getSingle();
        expect(local.name, 'Ramesh Reddy');
        expect(local.dirty, isTrue);

        // Back online: everything applied, rows clean.
        final engine = engineFor(deps.db, deps.api, clock: deps.clock);
        addTearDown(engine.dispose);
        final report = await engine.syncNow();
        expect(report.ok, isTrue);
        expect(report.applied, 8);
        expect(deps.api.appliedOps.map((o) => o.entity), <String>[
          'farmer',
          'farm',
          'crop_plot',
          'farm',
          'crop_plot',
          'crop_plot',
          'consent_record',
          'consent_record',
        ]);
        expect(
          deps.api.appliedOps.first.payload.containsKey(
            phoneVerificationExpiresKey,
          ),
          isFalse,
        );
        expect(
          (await deps.db.select(deps.db.farmers).getSingle()).dirty,
          isFalse,
        );
        expect(
          (await deps.db.select(deps.db.farms).get()).every(
            (f) => !f.dirty && f.version == 1,
          ),
          isTrue,
        );
        expect(
          (await deps.db.select(deps.db.cropPlots).get()).every(
            (p) => !p.dirty,
          ),
          isTrue,
        );
        expect(
          await SyncStore(deps.db).opsIn(<String>['queued', 'rejected']),
          isEmpty,
        );
      },
    );

    test('save refuses an incomplete draft and keeps it', () async {
      await wizard.start();
      await wizard.setName('Only a name');
      final issues = await wizard.save();
      expect(issues, isNotEmpty);
      expect(issues, contains(StepIssue.consentRequired));
      expect(st().savedFarmerId, isNull);
      expect(await deps.db.getValue(RegistrationDraft.kvKey), isNotNull);
      expect(await deps.db.select(deps.db.outboxTable).get(), isEmpty);
    });

    test('verify later saves the farmer unverified without a token', () async {
      deps.connectivity.online = false;
      await wizard.start();
      await wizard.setName('Ramesh');
      await wizard.setPhone('9876543210');
      await wizard.setVillage('village-1');
      await wizard.setLanguage('te');
      await wizard.verifyLater();
      await wizard.next();
      await fillFarm(
        ring: squareHectare,
        acres: 2.5,
        plots: <(String, DateTime)>[('pilot:cotton', DateTime(2026, 6, 15))],
      );
      await wizard.setConsentData(granted: true);
      expect(await wizard.save(), isEmpty);
      final farmer = await deps.db.select(deps.db.farmers).getSingle();
      expect(farmer.phoneVerified, isFalse);
      final op = (await SyncStore(deps.db).opsIn(<String>['queued'])).first;
      expect(
        SyncStore.payloadOf(op).containsKey(phoneVerificationTokenKey),
        isFalse,
      );
    });
  });

  group('A23 farm mode', () {
    test(
      'add a second farm to an existing farmer queues farm + plots only',
      () async {
        await seedSyncedFarmer(
          deps.db,
          id: 'f-existing',
          phone: '+919000000001',
        );
        await wizard.start(mode: DraftMode.farm, farmerId: 'f-existing');
        expect(wizard.steps, <RegistrationStep>[
          RegistrationStep.boundary,
          RegistrationStep.crops,
        ]);
        await fillFarm(
          ring: squareHectare,
          acres: 2.5,
          plots: <(String, DateTime)>[('pilot:maize', DateTime(2026, 6, 3))],
        );
        await wizard.next();
        expect(wizard.currentStep, RegistrationStep.crops);
        expect(await wizard.save(), isEmpty);
        expect(st().savedFarmerId, 'f-existing');
        expect(st().savedFarmId, isNotNull);
        final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
        expect(ops.map((o) => '${o.entity}:${o.action}'), <String>[
          'farm:create',
          'crop_plot:create',
        ]);
        expect(SyncStore.payloadOf(ops[0])['farmer_id'], 'f-existing');
      },
    );

    test('editing an existing farm updates it and reconciles plots', () async {
      await seedSyncedFarmer(deps.db, id: 'f-existing', phone: '+919000000001');
      final entities = LocalEntities(deps.db);
      await entities.write(
        SyncEntities.farm,
        'farm-1',
        farmPayload('f-existing'),
        version: 3,
        dirty: false,
        now: t0,
      );
      await entities.write(
        SyncEntities.cropPlot,
        'plot-1',
        cropPlotPayload('farm-1'),
        version: 2,
        dirty: false,
        now: t0,
      );
      await entities.write(
        SyncEntities.cropPlot,
        'plot-2',
        <String, Object?>{
          ...cropPlotPayload('farm-1'),
          'crop_id': 'crop-paddy',
        },
        version: 1,
        dirty: false,
        now: t0,
      );
      await wizard.start(
        mode: DraftMode.farm,
        farmerId: 'f-existing',
        farmId: 'farm-1',
      );
      final farm = draft().farm!;
      expect(farm.existing, isTrue);
      expect(farm.boundary, hasLength(4));
      expect(farm.declaredAcres, 2.5);
      expect(farm.plots.map((p) => p.id), <String>['plot-1', 'plot-2']);
      expect(farm.plots.first.sowingDate, DateTime(2026, 6, 15));

      await wizard.setDeclaredAcres(3);
      await wizard.updatePlot('plot-1', variety: 'Bt-II');
      await wizard.removePlot('plot-2');
      await wizard.addPlot();
      await wizard.updatePlot(
        draft().farm!.plots.last.id,
        cropId: 'pilot:tomato',
        sowingDate: DateTime(2026, 10, 5),
      );
      expect(await wizard.save(), isEmpty);
      final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
      expect(ops.map((o) => '${o.entity}:${o.action}:${o.entityId}'), <String>[
        'farm:update:farm-1',
        'crop_plot:update:plot-1',
        'crop_plot:create:${draft().farm!.plots.last.id}',
        'crop_plot:delete:plot-2',
      ]);
      expect(ops[0].baseVersion, 3);
      expect(SyncStore.payloadOf(ops[0])['area_acres'], 3);
      expect(ops[1].baseVersion, 2);
      expect(SyncStore.payloadOf(ops[1])['variety'], 'Bt-II');
      expect(SyncStore.payloadOf(ops[2])['season'], 'rabi');
      final plot2 = await entities.read(SyncEntities.cropPlot, 'plot-2');
      expect(plot2!.deleted, isTrue);
    });
  });
}
