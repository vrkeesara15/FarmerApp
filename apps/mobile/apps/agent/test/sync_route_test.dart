import 'package:farmerapp_agent/app.dart';
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// FA-025: A63 shows the live sync pill and opens A64 Sync details, where
/// queued items are listed and "Sync now" pushes them.
void main() {
  testWidgets('A63 sync row → A64 lists pending items and syncs them', (
    tester,
  ) async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final api = FakeSyncApi();
    final outbox = Outbox(db);
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', <String, Object?>{
      'name': 'Ramesh Reddy',
      'phone': '+919876543210',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncApiProvider.overrideWithValue(api),
          routerProvider.overrideWithValue(
            buildRouter(initialLocation: AppRoutes.settings),
          ),
        ],
        child: const MitraApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sync-setting')), findsOneWidget);
    expect(find.text('Pending 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync-setting')));
    await tester.pumpAndSettle();
    expect(find.byType(SyncDetailsScreen), findsOneWidget);
    expect(find.text('Sync details'), findsOneWidget);
    expect(find.text('Waiting to sync (1)'), findsOneWidget);
    expect(find.text('New farmer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pumpAndSettle();
    expect(find.text('Everything is synced'), findsOneWidget);
    expect(api.appliedOps.single.payload['name'], 'Ramesh Reddy');

    // Back on A63 the pill is green again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('A63 "Sync now" pushes without leaving the screen', (
    tester,
  ) async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final api = FakeSyncApi();
    await Outbox(db)
        .enqueueCreate(SyncEntities.farm, 'farm-1', {'farmer_id': 'f-1'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncApiProvider.overrideWithValue(api),
          routerProvider.overrideWithValue(
            buildRouter(initialLocation: AppRoutes.settings),
          ),
        ],
        child: const MitraApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sync-now-setting')));
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsOneWidget);
    expect(api.appliedOps, hasLength(1));
    expect(find.byType(SyncDetailsScreen), findsNothing);
  });
}
