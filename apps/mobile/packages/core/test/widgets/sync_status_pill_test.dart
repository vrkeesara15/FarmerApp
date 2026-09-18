import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('synced state', (tester) async {
    await tester.pumpWidget(
      harness(const SyncStatusPill(state: SyncState.synced)),
    );
    expect(find.text('Synced'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('pending state shows the count', (tester) async {
    await tester.pumpWidget(
      harness(const SyncStatusPill(state: SyncState.pending, pendingCount: 7)),
    );
    expect(find.text('Pending 7'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
  });

  testWidgets('failed state', (tester) async {
    await tester.pumpWidget(
      harness(const SyncStatusPill(state: SyncState.failed)),
    );
    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('syncing state', (tester) async {
    await tester.pumpWidget(
      harness(const SyncStatusPill(state: SyncState.syncing, pendingCount: 4)),
    );
    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_sync_outlined), findsOneWidget);
  });

  testWidgets('tap opens details', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      harness(SyncStatusPill(state: SyncState.failed, onTap: () => taps++)),
    );
    await tester.tap(find.text('Sync failed'));
    expect(taps, 1);
  });

  testWidgets('Telugu strings resolve', (tester) async {
    await tester.pumpWidget(
      harness(
        const SyncStatusPill(state: SyncState.pending, pendingCount: 2),
        locale: const Locale('te'),
      ),
    );
    expect(find.text('2 పెండింగ్'), findsOneWidget);
  });
}
