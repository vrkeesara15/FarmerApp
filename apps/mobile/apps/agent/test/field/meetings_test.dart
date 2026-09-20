import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_agent/screens/field/meetings_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';

/// A farmer QR token as the farmer app renders it (`GET /v1/me/attendance-qr`).
const String qrPayload =
    'farmerapp://attendance?token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmYXJtZXItMSJ9.sig';

Future<String> _startMeeting(WidgetTester tester, AgentDeps deps) async {
  await tester.tap(find.byKey(const Key('meeting-new')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('meeting-topic')),
    'Cotton pest management',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('meeting-create')));
  await tester.pumpAndSettle();
  final c = deps.container();
  addTearDown(c.dispose);
  final meetings = await c.read(fieldRepositoryProvider).meetings();
  return meetings.single.id;
}

void main() {
  test('a farmer attendance QR is read, anything else is refused', () {
    expect(parseAttendanceQr(qrPayload), endsWith('.sig'));
    expect(parseAttendanceQr('https://example.com/?token=abc'), isNull);
    expect(parseAttendanceQr('just some text'), isNull);
    expect(parseAttendanceQr('a.b.c'), 'a.b.c');
  });

  testWidgets('a meeting is created at the village meeting point', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.meetings));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('meetings-empty')), findsOneWidget);
    final id = await _startMeeting(tester, deps);

    final rows = await SyncStore(deps.db).opsIn(<String>['queued']);
    final op = SyncStore.toOp(
      rows.firstWhere((r) => r.entity == FieldEntities.farmerMeeting),
    );
    expect(op.entityId, id);
    expect(op.payload['village_id'], 'village-1');
    expect(op.payload['topic'], 'Cotton pest management');
    expect(op.payload['checkin_point'], isA<Map<String, Object?>>());
  });

  testWidgets('attendance by farmer OTP is recorded and queued', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    await seedSyncedFarmer(deps.db, id: 'farmer-1', phone: '+919000000001');
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.meetings));
    await tester.pumpAndSettle();
    final id = await _startMeeting(tester, deps);

    await tester.tap(find.byKey(const Key('meeting-add-otp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting-pick-farmer-1')));
    await tester.pumpAndSettle();
    expect(deps.field.otps, <(String, String)>[(id, 'farmer-1')]);

    await tester.enterText(
      find.descendant(
        of: find.byType(OtpInput),
        matching: find.byType(TextField),
      ),
      '123456',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting-otp-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attendee-farmer-1')), findsOneWidget);
    expect(find.text('1 present'), findsOneWidget);
    final rows = await SyncStore(deps.db).opsIn(<String>['queued']);
    final op = SyncStore.toOp(
      rows.firstWhere((r) => r.entity == FieldEntities.meetingAttendance),
    );
    expect(op.payload['method'], 'otp');
    expect(op.payload['farmer_id'], 'farmer-1');
    expect(op.payload['code'], '123456');
  });

  testWidgets('the OTP path says so when there is no network', (tester) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    await seedSyncedFarmer(deps.db, id: 'farmer-1', phone: '+919000000001');
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.meetings));
    await tester.pumpAndSettle();
    await _startMeeting(tester, deps);
    deps.field.offline = true;

    await tester.tap(find.byKey(const Key('meeting-add-otp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting-pick-farmer-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('meeting-otp-offline')), findsOneWidget);
  });

  testWidgets('attendance by QR works offline and finishes the meeting', (
    tester,
  ) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    deps.scanner.enqueue(qrPayload);
    deps.field.offline = true;
    deps.api.offline = true;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.meetings));
    await tester.pumpAndSettle();
    await _startMeeting(tester, deps);

    await tester.tap(find.byKey(const Key('meeting-add-qr')));
    await tester.pumpAndSettle();

    expect(find.text('1 present'), findsOneWidget);
    final rows = await SyncStore(deps.db).opsIn(<String>['queued']);
    final op = SyncStore.toOp(
      rows.firstWhere((r) => r.entity == FieldEntities.meetingAttendance),
    );
    expect(op.payload['method'], 'qr');
    expect(op.payload['token'], endsWith('.sig'));
    // The scan time travels with the op; the server validates against it.
    expect(op.payload['recorded_at'], isA<String>());

    await tester.tap(find.byKey(const Key('meeting-finish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meeting-closed')), findsOneWidget);
    expect(find.byKey(const Key('meeting-add-qr')), findsNothing);
  });

  testWidgets('a QR that is not an attendance code is refused', (tester) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    deps.scanner.enqueue('https://example.com/nothing');
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.meetings));
    await tester.pumpAndSettle();
    await _startMeeting(tester, deps);

    await tester.tap(find.byKey(const Key('meeting-add-qr')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('meeting-qr-invalid')), findsOneWidget);
    expect(find.text('0 present'), findsOneWidget);
  });
}
