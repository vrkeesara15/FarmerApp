// Goldens for A30 (inside / outside), A31, A32 (choose / QR waiting /
// confirmed), A33 and A34 in Light and Sunlight at 360x800.
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import '../visits/visit_test_support.dart';

void main() {
  for (final mode in AppThemeMode.values) {
    group(mode.name, () {
      Future<void> golden(
        WidgetTester tester,
        String name,
        String Function(AgentDeps deps, String? visitId) location, {
        double east = 50,
        bool withVisit = false,
        Future<void> Function(AgentDeps deps, String visitId)? prepare,
      }) async {
        usePhoneSurface(tester);
        final deps = AgentDeps();
        addTearDown(deps.dispose);
        await seedVisitWorld(deps, east: east);
        String? id;
        if (withVisit) {
          id = await seedVisit(deps);
          await prepare?.call(deps, id);
        }
        await tester.pumpWidget(
          deps.app(initialLocation: location(deps, id), theme: mode),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${mode.name}.png'),
        );
      }

      testWidgets('a30_start_visit_inside', (tester) async {
        await golden(
          tester,
          'a30_start_visit_inside',
          (_, _) => '/visits/new?farmerId=f-1&farmId=farm-f-1',
        );
      });

      testWidgets('a30_start_visit_outside', (tester) async {
        await golden(
          tester,
          'a30_start_visit_outside',
          (_, _) => '/visits/new?farmerId=f-1&farmId=farm-f-1',
          east: 600,
        );
      });

      testWidgets('a31_visit_in_progress', (tester) async {
        await golden(
          tester,
          'a31_visit_in_progress',
          (_, id) => '/visits/$id',
          withVisit: true,
          prepare: (deps, id) async {
            deps.now = deps.now.add(const Duration(minutes: 3, seconds: 20));
          },
        );
      });

      testWidgets('a32_confirm_choose', (tester) async {
        await golden(
          tester,
          'a32_confirm_choose',
          (_, id) => '/visits/$id/confirm',
          withVisit: true,
        );
      });

      testWidgets('a32_confirm_qr_waiting', (tester) async {
        await golden(
          tester,
          'a32_confirm_qr_waiting',
          (_, id) => '/visits/$id/confirm',
          withVisit: true,
          prepare: (deps, id) async {
            final c = deps.container();
            await c
                .read(visitFlowProvider)
                .requestConfirmation(id, ConfirmationChannel.qr);
            c.dispose();
          },
        );
      });

      testWidgets('a32_confirm_confirmed', (tester) async {
        await golden(
          tester,
          'a32_confirm_confirmed',
          (_, id) => '/visits/$id/confirm',
          withVisit: true,
          prepare: (deps, id) async {
            final c = deps.container();
            final flow = c.read(visitFlowProvider);
            await flow.requestConfirmation(id, ConfirmationChannel.smsOtp);
            await flow.confirmOtp(id, '123456');
            c.dispose();
          },
        );
      });

      testWidgets('a33_summary', (tester) async {
        await golden(
          tester,
          'a33_summary',
          (_, id) => '/visits/$id/summary',
          withVisit: true,
          prepare: (deps, id) async {
            deps.now = deps.now.add(const Duration(minutes: 4));
            final c = deps.container();
            await c.read(visitFlowProvider).checkOut(id, notes: 'Aphids');
            c.dispose();
          },
        );
      });

      testWidgets('a34_visits_list', (tester) async {
        await golden(
          tester,
          'a34_visits_list',
          (_, _) => AppRoutes.visits,
          withVisit: true,
          prepare: (deps, id) async {
            // A scored visit earlier in the day (server row) and the open
            // one still queued.
            await LocalEntities(deps.db).write(
              SyncEntities.visit,
              'visit-scored',
              <String, Object?>{
                'farmer_id': 'f-1',
                'purpose': 'advisory',
                'checkin_at': deps.now
                    .subtract(const Duration(hours: 2))
                    .toIso8601String(),
                'checkin_point': <String, Object?>{'lat': 17.4, 'lon': 78.4},
                'checkout_at': deps.now
                    .subtract(const Duration(hours: 1, minutes: 35))
                    .toIso8601String(),
                'duration_s': 1500,
                'score': 70,
                'status': 'verified',
              },
              version: 3,
              dirty: false,
              now: deps.now,
            );
          },
        );
      });
    });
  }
}
