import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';
import 'commerce_harness.dart';

/// FA-022 khata: fetched page by page, cached for offline viewing with its
/// "as of" time; the balance shown equals the sum of the entries shown.
void main() {
  test('pages are merged into one ledger', () {
    final first = sampleKhata()
      ..['entries'] = (sampleKhata()['entries']! as List).sublist(0, 2)
      ..['next_cursor'] = 'c1';
    final second = <String, Object?>{
      ...sampleKhata(),
      'entries': (sampleKhata()['entries']! as List).sublist(2),
    };
    final merged = mergeKhataPages(<Map<String, Object?>>[first, second]);
    expect((merged['entries']! as List).length, 4);
    expect(merged['next_cursor'], isNull);
    final view = KhataView.fromJson(merged, asOf: t0);
    expect(view.displayedBalancePaise, view.balancePaise);
  });

  test('balance equals the sum of the entries; buckets; due dates', () {
    final view = KhataView.fromJson(sampleKhata(), asOf: t0);
    expect(view.entries, hasLength(4));
    expect(
      view.entries.fold<int>(0, (a, e) => a + e.signedPaise),
      view.balancePaise,
    );
    expect(view.displayedBalancePaise, 1250000);
    expect(view.buckets, <OverdueBucket, int>{
      OverdueBucket.d0to30: 250000,
      OverdueBucket.d31to60: 0,
      OverdueBucket.d61to90: 400000,
      OverdueBucket.d90plus: 0,
    });
    expect(
      view.buckets.values.fold<int>(0, (a, b) => a + b),
      view.overduePaise,
    );
    final latest = view.entries.first;
    expect(latest.isDebit, isTrue);
    expect(latest.dueDate, DateTime.utc(2026, 11, 30));
    expect(latest.harvestMonth, DateTime.utc(2026, 11));
    expect(view.entries[1].isDebit, isFalse);
    expect(view.entries[1].signedPaise, -300000);
    expect(view.collectStoreId, storeId);
    expect(view.balanceAt(storeId), 1250000);
    expect(view.limitsByStore[storeId], 2000000);
    expect(view.payments.single.mode, 'cash');
  });

  test('refresh caches; offline keeps the cached khata and its time', () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final api = FakeKhataApi()..khatas['f-1'] = sampleKhata();
    var now = t0;
    final repo = KhataRepository(db, api, clock: () => now);
    expect(await repo.read('f-1'), isNull);
    expect(await repo.refresh('f-1'), isTrue);
    api.offline = true;
    now = t0.add(const Duration(hours: 3));
    expect(await repo.refresh('f-1'), isFalse);
    final cached = (await repo.read('f-1'))!;
    expect(cached.asOf, t0);
    expect(cached.displayedBalancePaise, 1250000);
  });

  testWidgets('KhataLedger shows a balance equal to the entries it lists', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final view = KhataView.fromJson(sampleKhata(), asOf: t0);
    await tester.pumpWidget(
      harness(
        SingleChildScrollView(
          child: KhataLedger(
            balancePaise: view.displayedBalancePaise,
            now: t0,
            entries: <KhataEntry>[
              for (final e in view.entries)
                KhataEntry(
                  dateUtc: e.createdAt,
                  description: e.refType,
                  amountPaise: e.amountPaise,
                  isCredit: !e.isDebit,
                  dueDateUtc: e.dueDate,
                  harvestMonthUtc: e.harvestMonth,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var sum = 0;
    for (final e in view.entries) {
      final text = '${e.isDebit ? '+' : '-'}${formatInr(e.amountPaise)}';
      expect(find.text(text), findsOneWidget);
      sum += e.signedPaise;
    }
    expect(find.text(formatInr(sum)), findsOneWidget);
    expect(find.text('Due 30-11-2026 · harvest 11-2026'), findsOneWidget);
  });
}
