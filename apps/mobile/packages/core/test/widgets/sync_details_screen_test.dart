import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sync/sync_harness.dart';

/// A64 Sync details over a real engine: pending and failed items, error
/// detail, retry / discard, "Sync now", last sync time, five languages.
void main() {
  late AppDatabase db;
  late FakeSyncApi api;
  late Outbox outbox;
  late FakeClock clock;

  setUp(() {
    db = newDb();
    api = FakeSyncApi();
    clock = FakeClock(t0);
    outbox = outboxFor(db, clock: clock, ids: SeqIds());
  });

  tearDown(() => db.close());

  Widget app({Locale locale = const Locale('en')}) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      syncApiProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      theme: AppTheme.build(AppThemeMode.light, locale: locale),
      locale: locale,
      localizationsDelegates: CoreLocalizations.localizationsDelegates,
      supportedLocales: CoreLocalizations.supportedLocales,
      home: const SyncDetailsScreen(),
    ),
  );

  testWidgets('empty state before the first sync', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Sync details'), findsOneWidget);
    expect(find.text('Not synced yet'), findsOneWidget);
    expect(find.text('Everything is synced'), findsOneWidget);
    expect(find.byKey(const Key('sync-now')), findsOneWidget);
    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('pending and failed items with error, retry and discard', (
    tester,
  ) async {
    api.validate = (op) => op.entityId == 'f-bad'
        ? const SyncError('duplicate_phone', 'Phone already registered')
        : null;
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-bad', farmerPayload(1));
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-ok', farmerPayload(2));
    final farmOp = await outbox.enqueueCreate(
      SyncEntities.farm,
      'farm-1',
      farmPayload('f-ok'),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Waiting to sync (3)'), findsOneWidget);
    expect(find.text('New farmer'), findsNWidgets(2));
    expect(find.text('New farm'), findsOneWidget);
    expect(find.text('Saved 20-09-2026 06:00'), findsNWidgets(3));
    expect(find.text('Pending 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pumpAndSettle();
    expect(find.text('Needs attention (1)'), findsOneWidget);
    expect(find.text('Phone already registered'), findsOneWidget);
    expect(find.text('Waiting to sync'), findsNothing);
    expect(find.textContaining('Last synced '), findsOneWidget);
    expect(find.text('Not synced yet'), findsNothing);
    expect(find.text('Sync failed'), findsOneWidget);
    expect(api.appliedOps.map((o) => o.opId), contains(farmOp.opId));

    // Retry after the user fixed the phone.
    api.validate = null;
    await outbox.enqueueUpdate(SyncEntities.farmer, 'f-bad', {
      'phone': '+919876500009',
    });
    await tester.pumpAndSettle();
    expect(find.text('Waiting to sync (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pumpAndSettle();
    expect(find.text('Everything is synced'), findsOneWidget);
    expect(api.row('farmer', 'f-bad')!.data['phone'], '+919876500009');
  });

  testWidgets('Retry and Discard buttons act on one item', (tester) async {
    api.validate = (_) => const SyncError('validation_error');
    final a = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-a',
      farmerPayload(1),
    );
    final b = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-b',
      farmerPayload(2),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pumpAndSettle();
    expect(find.text('Needs attention (2)'), findsOneWidget);
    expect(
      find.text('The server did not accept this item. Edit it and retry.'),
      findsNWidgets(2),
    );

    await tester.ensureVisible(find.byKey(Key('sync-discard-${b.opId}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('sync-discard-${b.opId}')));
    await tester.pumpAndSettle();
    expect(find.text('Needs attention (1)'), findsOneWidget);

    api.validate = null;
    await tester.ensureVisible(find.byKey(Key('sync-retry-${a.opId}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('sync-retry-${a.opId}')));
    await tester.pumpAndSettle();
    expect(find.text('Waiting to sync (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pumpAndSettle();
    expect(find.text('Everything is synced'), findsOneWidget);
    expect(api.appliedOps.map((o) => o.opId), [a.opId]);
  });

  testWidgets('Retry all requeues every rejected item', (tester) async {
    api.validate = (_) => const SyncError('validation_error', 'x');
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-a', farmerPayload(1));
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-b', farmerPayload(2));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sync-retry-all')));
    await tester.pumpAndSettle();
    expect(find.text('Waiting to sync (2)'), findsOneWidget);
  });

  testWidgets('a transport failure is explained with the next attempt', (
    tester,
  ) async {
    api.offline = true;
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-a', farmerPayload(1));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not reach the server. It will try again on its own.'),
      findsOneWidget,
    );
    expect(find.textContaining('Next attempt'), findsOneWidget);
    expect(find.text('Pending 1'), findsOneWidget);
  });

  testWidgets('a photo still uploading is shown on its item', (tester) async {
    final uploadId = await outbox.enqueueUpload(
      filePath: '/p/1.jpg',
      bytes: photoBytes(10),
      purpose: 'farm_photo',
    );
    await outbox.enqueueCreate(
      SyncEntities.farm,
      'farm-1',
      farmPayload('f-1', photos: <Object?>[Outbox.uploadRef(uploadId)]),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Waiting to sync (2)'), findsOneWidget);
    expect(find.text('Photos uploading: 1'), findsOneWidget);
    expect(find.text('Waiting for the photo to upload'), findsOneWidget);
  });

  for (final (locale, title, pending) in <(Locale, String, String)>[
    (const Locale('te'), 'సింక్ వివరాలు', 'సింక్ కోసం వేచి ఉన్నవి (1)'),
    (const Locale('kn'), 'ಸಿಂಕ್ ವಿವರಗಳು', 'ಸಿಂಕ್‌ಗೆ ಕಾಯುತ್ತಿರುವವು (1)'),
    (const Locale('hi'), 'सिंक विवरण', 'सिंक की प्रतीक्षा में (1)'),
    (const Locale('mr'), 'सिंक तपशील', 'सिंकची वाट पाहत आहेत (1)'),
  ]) {
    testWidgets('${locale.languageCode} strings resolve', (tester) async {
      await outbox.enqueueCreate(SyncEntities.farmer, 'f-a', farmerPayload(1));
      await tester.pumpWidget(app(locale: locale));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(pending), findsOneWidget);
      final l10n = lookupCoreLocalizations(locale);
      expect(
        find.text(
          l10n.syncItemTitle(l10n.syncActionCreate, l10n.syncEntityFarmer),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.syncNow), findsOneWidget);
    });
  }
}
