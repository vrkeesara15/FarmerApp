import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-007 F42 crop calendar: it regenerates when the sowing date changes
/// and keeps the tasks the farmer already finished, the reminder toggle
/// persists and queues offline, and the whole screen reads from the
/// cache.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('calendar data', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedAdvisory();
      await deps.signIn();
    });
    tearDown(() => deps.dispose());

    test(
      'regenerates when the sowing date changes and keeps done tasks',
      () async {
        final c = deps.container();
        addTearDown(c.dispose);
        final repo = c.read(advisoryRepositoryProvider);
        await repo.refreshCalendar();

        final before = await repo.watchCalendar().first;
        final plotBefore = before!.value.plot('plot-1')!;
        expect(plotBefore.sowingDate, DateTime.utc(2026, 6, 15));
        final doneBefore = plotBefore.tasks.firstWhere((t) => t.id == 'task-1');
        expect(doneBefore.done, isTrue);
        final pendingBefore = plotBefore.tasks.firstWhere(
          (t) => t.id == 'task-3',
        );

        // The farmer corrected the sowing date: the server moves the
        // pending tasks and leaves the done one alone.
        deps.advisory.moveSowingDate('plot-1', DateTime.utc(2026, 6, 25));
        await repo.refreshCalendar();

        final after = await repo.watchCalendar().first;
        final plotAfter = after!.value.plot('plot-1')!;
        expect(plotAfter.sowingDate, DateTime.utc(2026, 6, 25));
        final doneAfter = plotAfter.tasks.firstWhere((t) => t.id == 'task-1');
        expect(doneAfter.done, isTrue, reason: 'done tasks are never touched');
        expect(doneAfter.dueDate, doneBefore.dueDate);
        final pendingAfter = plotAfter.tasks.firstWhere(
          (t) => t.id == 'task-3',
        );
        expect(
          pendingAfter.dueDate,
          pendingBefore.dueDate.add(const Duration(days: 10)),
        );

        // ... and the app has a "what changed" note for F42.
        final change = await repo.watchCalendarChange('plot-1').first;
        expect(change, isNotNull);
        expect(change!.movedDays, 10);
        expect(change.moved, 3, reason: 'three pending tasks moved');
        expect(change.added, 0);
        expect(change.removed, 0);

        await repo.dismissCalendarChange('plot-1');
        expect(await repo.watchCalendarChange('plot-1').first, isNull);
      },
    );

    test('a reminder toggle is sent online and survives a refresh', () async {
      final c = deps.container();
      addTearDown(c.dispose);
      final repo = c.read(advisoryRepositoryProvider);
      await repo.refreshCalendar();
      final task = (await repo.watchCalendar().first)!.value
          .plot('plot-1')!
          .tasks
          .firstWhere((t) => t.id == 'task-3');
      expect(task.reminderEnabled, isTrue);

      expect(await repo.setTaskReminder(task, on: false), KisanWrite.done);
      expect(deps.advisory.writes.last.$1, 'PATCH /v1/calendar/tasks/task-3');
      expect(deps.advisory.writes.last.$2['reminder_enabled'], isFalse);
      expect(deps.advisory.writes.last.$2['version'], task.version);

      await repo.refreshCalendar();
      final again = (await repo.watchCalendar().first)!.value
          .plot('plot-1')!
          .tasks
          .firstWhere((t) => t.id == 'task-3');
      expect(again.reminderEnabled, isFalse);
    });

    test('offline, the toggle is applied locally and queued', () async {
      final c = deps.container();
      addTearDown(c.dispose);
      final repo = c.read(advisoryRepositoryProvider);
      await repo.refreshCalendar();
      final task = (await repo.watchCalendar().first)!.value
          .plot('plot-1')!
          .tasks
          .firstWhere((t) => t.id == 'task-3');

      deps.advisory.offline = true;
      deps.connectivity.online = false;
      expect(await repo.setTaskReminder(task, on: false), KisanWrite.queued);

      final local = (await repo.watchCalendar().first)!.value
          .plot('plot-1')!
          .tasks
          .firstWhere((t) => t.id == 'task-3');
      expect(local.reminderEnabled, isFalse);
      expect(local.pending, isTrue, reason: 'the row shows it is queued');

      final rows = await c.read(outboxProvider).store.openOps();
      expect(rows, hasLength(1));
      final op = SyncStore.toOp(rows.single);
      expect(op.entity, SyncEntities.cropPlotTask);
      expect(op.entityId, 'task-3');
      expect(op.action, SyncAction.update);
      expect(op.payload['reminder_enabled'], isFalse);
    });

    test('marking a task done sends the status and keeps it', () async {
      final c = deps.container();
      addTearDown(c.dispose);
      final repo = c.read(advisoryRepositoryProvider);
      await repo.refreshCalendar();
      final task = (await repo.watchCalendar().first)!.value
          .plot('plot-2')!
          .tasks
          .single;

      expect(await repo.setTaskDone(task, done: true), KisanWrite.done);
      await repo.refreshCalendar();
      final again = (await repo.watchCalendar().first)!.value
          .plot('plot-2')!
          .tasks
          .single;
      expect(again.done, isTrue);
      expect(again.doneAt, isNotNull);
    });
  });

  group('F42 screen', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedAdvisory();
      await deps.signIn();
      await deps.primeAdvisory();
    });
    tearDown(() => deps.dispose());

    testWidgets('shows the tasks by week with audio and toggles', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await pumpApp(
        tester,
        deps.app(initialLocation: AppRoutes.calendar('plot-1')),
      );

      expect(find.byKey(const Key('calendar-week-1')), findsOneWidget);
      await scrollTo(tester, find.byKey(const Key('task-task-3')));
      expect(find.text('Check for sucking pests'), findsOneWidget);
      expect(find.text('Spray only if you see the pest.'), findsOneWidget);
      // NF-009: every task can be read out.
      expect(
        find.byKey(const Key('audio-task_cotton.spray_1')),
        findsOneWidget,
      );

      await tapIt(tester, find.byKey(const Key('task-reminder-task-3')));
      expect(deps.advisory.writes.last.$2['reminder_enabled'], isFalse);
      expect(find.text('No reminder'), findsWidgets);
    });

    testWidgets('shows the "what changed" note and hides it on Got it', (
      tester,
    ) async {
      deps.advisory.moveSowingDate('plot-1', DateTime.utc(2026, 6, 25));
      await deps.primeAdvisory();

      usePhoneSurface(tester);
      await pumpApp(
        tester,
        deps.app(initialLocation: AppRoutes.calendar('plot-1')),
      );
      expect(find.byKey(const Key('calendar-changed')), findsOneWidget);
      expect(
        find.text('The work you already finished stays finished.'),
        findsOneWidget,
      );

      await tapIt(tester, find.byKey(const Key('calendar-changed-ok')));
      expect(find.byKey(const Key('calendar-changed')), findsNothing);
    });

    testWidgets('works offline from the cache', (tester) async {
      deps.advisory.offline = true;
      deps.connectivity.online = false;
      usePhoneSurface(tester);
      await pumpApp(
        tester,
        deps.app(initialLocation: AppRoutes.calendar('plot-1')),
      );
      expect(find.byType(OfflineBanner), findsOneWidget);
      await scrollTo(tester, find.byKey(const Key('task-task-3')));
      await scrollTo(tester, find.byKey(const Key('as-of')));
    });

    testWidgets('F40 shows the next task and opens the calendar', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.crops));
      await scrollTo(tester, find.byKey(const Key('plot-next-plot-1')));
      expect(find.textContaining('Next:'), findsWidgets);
      await tapIt(tester, find.byKey(const Key('plot-calendar-plot-1')));
      expect(find.byKey(const Key('calendar-week-1')), findsOneWidget);
    });
  });
}
