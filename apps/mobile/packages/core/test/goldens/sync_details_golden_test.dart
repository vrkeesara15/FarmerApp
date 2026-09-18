// Goldens for A64 Sync details in Light and Sunlight at 360x800.
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';
import '../sync/sync_harness.dart';

final DateTime _queued = DateTime.utc(2026, 9, 20, 4, 12);

final SyncDetails _busy = SyncDetails(
  status: const SyncStatus(SyncStatusKind.failed, pending: 3, failed: 1),
  lastSyncAt: DateTime.utc(2026, 9, 19, 12, 40),
  lastError: const SyncError('transport', 'offline'),
  nextAttemptAt: DateTime.utc(2026, 9, 20, 4, 35),
  pendingUploads: 1,
  pending: <SyncItem>[
    SyncItem(
      opId: 'op-2',
      entity: SyncEntities.farmer,
      action: SyncAction.create,
      entityId: 'f-2',
      clientTs: _queued,
      state: OutboxState.queued,
    ),
    SyncItem(
      opId: 'op-3',
      entity: SyncEntities.farm,
      action: SyncAction.create,
      entityId: 'farm-2',
      clientTs: _queued.add(const Duration(minutes: 4)),
      state: OutboxState.queued,
      waitingForUpload: true,
    ),
  ],
  failed: <SyncItem>[
    SyncItem(
      opId: 'op-1',
      entity: SyncEntities.farmer,
      action: SyncAction.create,
      entityId: 'f-1',
      clientTs: _queued.subtract(const Duration(hours: 1)),
      state: OutboxState.rejected,
      error: const SyncError('duplicate_phone', 'Phone already registered'),
    ),
  ],
);

const SyncDetails _empty = SyncDetails(
  status: SyncStatus.synced,
  pending: <SyncItem>[],
  failed: <SyncItem>[],
);

void main() {
  for (final mode in AppThemeMode.values) {
    group(mode.name, () {
      for (final (name, details) in <(String, SyncDetails)>[
        ('a64_sync_details', _busy),
        ('a64_sync_details_empty', _empty),
      ]) {
        testWidgets(name, (tester) async {
          usePhoneSurface(tester);
          final db = newDb();
          addTearDown(db.close);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(db),
                syncDetailsProvider.overrideWith(
                  (ref) => Stream<SyncDetails>.value(details),
                ),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.build(mode, locale: const Locale('en')),
                localizationsDelegates:
                    CoreLocalizations.localizationsDelegates,
                supportedLocales: CoreLocalizations.supportedLocales,
                home: const SyncDetailsScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/${name}_${mode.name}.png'),
          );
        });
      }
    });
  }
}
