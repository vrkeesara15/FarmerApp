import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/delete_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-015 (mobile): F70 → Delete my account → explanation (read aloud) →
/// second confirmation → `POST /v1/me/deletion-request` → ticket, status
/// and due date (`GET /v1/me/deletion-request` on the next visit).
void main() {
  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld();
    await deps.signIn();
  });
  tearDown(() => deps.dispose());

  testWidgets('two steps, then the ticket with its status and due date', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.me));
    await tapIt(tester, find.byKey(const Key('me-delete')));
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.byKey(const Key('delete-explain')), findsOneWidget);
    expect(find.byKey(const Key('audio-f70_delete_explain')), findsOneWidget);

    // Step 1 alone never sends anything.
    await tapIt(tester, find.byKey(const Key('delete-start')));
    expect(find.byKey(const Key('delete-confirm-step')), findsOneWidget);
    expect(deps.kisan.calls.where((c) => c.startsWith('POST')), isEmpty);
    // "No, keep my account" goes back.
    await tapIt(tester, find.byKey(const Key('delete-cancel')));
    expect(find.byKey(const Key('delete-explain')), findsOneWidget);

    await tapIt(tester, find.byKey(const Key('delete-start')));
    await tapIt(tester, find.byKey(const Key('delete-yes')));
    expect(deps.kisan.writes.last.$1, 'POST /v1/me/deletion-request');
    expect(find.byKey(const Key('delete-ticket')), findsOneWidget);
    expect(find.text('We got your request'), findsOneWidget);
    expect(find.text('Ticket DEL-1001'), findsOneWidget);
    expect(find.text('We will finish by 19-10-2026'), findsOneWidget);

    // F70 shows the request; reopening reads the status from the API.
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Request sent · DEL-1001'), findsOneWidget);
    deps.kisan.deletion!['status'] = 'processing';
    await tapIt(tester, find.byKey(const Key('me-delete')));
    expect(find.text('We are deleting your data'), findsOneWidget);
  });

  testWidgets('offline: nothing is sent and the farmer is told', (
    tester,
  ) async {
    usePhoneSurface(tester);
    deps.kisan.offline = true;
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.deleteAccount));
    await tapIt(tester, find.byKey(const Key('delete-start')));
    await tapIt(tester, find.byKey(const Key('delete-yes')));
    expect(
      find.text('This needs internet. Try again when online.'),
      findsOneWidget,
    );
    expect(deps.kisan.deletion, isNull);
    expect(find.byKey(const Key('delete-ticket')), findsNothing);
  });

  testWidgets('endpoint not deployed yet (404): a clear failure, no ticket', (
    tester,
  ) async {
    usePhoneSurface(tester);
    deps.kisan.deletionMissing = true;
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.deleteAccount));
    await tapIt(tester, find.byKey(const Key('delete-start')));
    await tapIt(tester, find.byKey(const Key('delete-yes')));
    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(find.byKey(const Key('delete-ticket')), findsNothing);
    expect(find.byType(AppButton), findsWidgets);
  });
}
