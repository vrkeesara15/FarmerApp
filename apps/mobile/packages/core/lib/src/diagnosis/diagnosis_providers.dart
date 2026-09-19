import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

import '../db/open_database.dart';
import '../farmers/farmers_providers.dart' show photoStoreProvider;
import '../security/security_providers.dart' show tenantSettingsProvider;
import '../sync/sync_providers.dart';
import 'diagnosis_api.dart';
import 'diagnosis_models.dart';
import 'diagnosis_repository.dart';
import 'guided_camera.dart';

/// `GET /v1/diagnoses/{id}`; the apps override it with [HttpDiagnosisApi].
final Provider<DiagnosisApi> diagnosisApiProvider = Provider<DiagnosisApi>(
  (ref) => FakeDiagnosisApi(),
);

/// The crop-doctor store.
final Provider<DiagnosisRepository> diagnosisRepositoryProvider =
    Provider<DiagnosisRepository>(
      (ref) => DiagnosisRepository(
        db: ref.watch(appDatabaseProvider),
        outbox: ref.watch(outboxProvider),
        photos: ref.watch(photoStoreProvider),
        api: ref.watch(diagnosisApiProvider),
        clock: ref.watch(clockProvider),
        ids: ref.watch(idGeneratorProvider),
      ),
    );

/// Opens the live camera for F21 / A40; the apps override it with
/// [PluginGuidedCamera].
final Provider<GuidedCameraFactory> guidedCameraFactoryProvider =
    Provider<GuidedCameraFactory>((ref) => FakeGuidedCamera.new);

/// Waits between result polls (tests make it controllable).
final Provider<Future<void> Function(Duration)> diagnosisPollSleepProvider =
    Provider<Future<void> Function(Duration)>((ref) => Future<void>.delayed);

/// Pushes queued diagnosis work (uploads, create op) when online; the
/// farmer app points it at its flush, the agent app at the sync engine.
final Provider<Future<void> Function()> diagnosisFlushProvider =
    Provider<Future<void> Function()>((ref) {
      return () async {
        if (!await ref.read(connectivityMonitorProvider).isOnline()) return;
        await ref.read(syncEngineProvider).syncNow();
      };
    });

/// Tenant flag `on_device_crop_guess` (default off until the model passes
/// field validation, ml/ondevice/INTEGRATION.md §7).
final Provider<bool> onDeviceCropGuessFlagProvider = Provider<bool>(
  (ref) => ref.watch(tenantSettingsProvider).value?.onDeviceCropGuess ?? false,
);

/// Whether the on-device crop guess may be shown and pre-select a crop.
final Provider<bool> onDeviceCropGuessEnabledProvider = Provider<bool>(
  (ref) => ref.watch(onDeviceCropGuessFlagProvider),
);

/// One diagnosis, live.
final StreamProviderFamily<Diagnosis?, String> diagnosisProvider =
    StreamProvider.family<Diagnosis?, String>(
      (ref, id) => ref.watch(diagnosisRepositoryProvider).watch(id),
    );

/// Every diagnosis on the phone (the farmer's own), newest first.
final StreamProvider<List<Diagnosis>> diagnosesProvider =
    StreamProvider<List<Diagnosis>>(
      (ref) => ref.watch(diagnosisRepositoryProvider).watchAll(),
    );

/// A farmer's diagnoses (A22 Diagnoses tab), newest first.
final StreamProviderFamily<List<Diagnosis>, String> farmerDiagnosesProvider =
    StreamProvider.family<List<Diagnosis>, String>(
      (ref, farmerId) =>
          ref.watch(diagnosisRepositoryProvider).watchAll(farmerId: farmerId),
    );
