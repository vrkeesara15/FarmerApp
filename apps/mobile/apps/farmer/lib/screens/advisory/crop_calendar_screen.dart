import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/advisory_widgets.dart';
import '../../widgets/kisan_widgets.dart';

/// F42 Crop calendar (FM-007): the plot's tasks week by week with a
/// pictogram, a short instruction in the farmer's language and an audio
/// button (NF-009), "done" and "remind me" per task, and a "what changed"
/// note when the sowing date moved. Everything is read from the synced
/// calendar, so it works offline; a change made offline is queued.
class CropCalendarScreen extends ConsumerWidget {
  /// Creates the screen.
  const CropCalendarScreen({required this.cropPlotId, super.key});

  /// The crop plot whose calendar is shown.
  final String cropPlotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final cached = ref.watch(cropCalendarProvider).value;
    final plot = cached?.value.plot(cropPlotId);
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          plot?.cropNameIn(lang) ?? l10n.calendarTitle,
          key: const Key('calendar-title'),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: RefreshOnOpen(
                onOpen: (ref) =>
                    ref.read(advisoryRepositoryProvider).refreshCalendar(),
                child: plot == null || plot.tasks.isEmpty
                    ? EmptyState(
                        icon: Icons.event_note_outlined,
                        title: l10n.calendarNoTasks,
                        help: l10n.calendarNoTasksHelp,
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref
                            .read(advisoryRepositoryProvider)
                            .refreshCalendar(),
                        child: _Timeline(
                          plot: plot,
                          today: cached!.value.today,
                          asOf: cached.asOf,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({
    required this.plot,
    required this.today,
    required this.asOf,
  });

  final CropPlotCalendar plot;
  final DateTime today;
  final DateTime asOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final weeks = plot.byWeek();
    final keys = weeks.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      children: <Widget>[
        _ChangedNote(cropPlotId: plot.cropPlotId),
        SpokenText(promptId: 'f42_help', text: l10n.calendarHelp),
        if (plot.sowingDate != null)
          Text(
            l10n.calendarSownOn(formatDateIst(plot.sowingDate!)),
            key: const Key('calendar-sown-on'),
            style: app.text.body.copyWith(color: app.palette.textSecondary),
          ),
        const SizedBox(height: Tokens.space3),
        for (final week in keys) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space2),
            child: Text(
              l10n.calendarWeek(week),
              key: Key('calendar-week-$week'),
              style: app.text.heading,
            ),
          ),
          for (final task in weeks[week]!)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space3),
              child: _TaskCard(task: task, today: today),
            ),
        ],
        AsOfLabel(asOf),
      ],
    );
  }
}

class _ChangedNote extends ConsumerWidget {
  const _ChangedNote({required this.cropPlotId});

  final String cropPlotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final change = ref.watch(calendarChangeProvider(cropPlotId)).value;
    if (change == null || change.isEmpty) return const SizedBox.shrink();
    final days = change.movedDays.abs();
    final what = days == 0
        ? l10n.calendarChangedTasks(change.moved + change.added)
        : change.movedDays > 0
        ? l10n.calendarChangedLater(days, change.moved)
        : l10n.calendarChangedEarlier(days, change.moved);
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space3),
      child: KisanCard(
        key: const Key('calendar-changed'),
        icon: Icons.update,
        title: l10n.calendarChangedTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(what, style: app.text.body),
            const SizedBox(height: Tokens.space1),
            Text(l10n.calendarChangedDoneKept, style: app.text.body),
            AudioButton(
              promptId: 'f42_changed',
              text: '$what ${l10n.calendarChangedDoneKept}',
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                key: const Key('calendar-changed-ok'),
                label: l10n.calendarGotIt,
                icon: Icons.check,
                size: AppButtonSize.medium,
                onPressed: () => ref
                    .read(advisoryRepositoryProvider)
                    .dismissCalendarChange(cropPlotId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task, required this.today});

  final CalendarTask task;
  final DateTime today;

  Future<void> _report(BuildContext context, KisanWrite result) async {
    final l10n = CoreLocalizations.of(context);
    showKisanMessage(context, switch (result) {
      KisanWrite.done => l10n.kisanSaved,
      KisanWrite.queued => l10n.calendarSavedOffline,
      KisanWrite.offline => l10n.kisanNeedsInternet,
      KisanWrite.refused => l10n.kisanSaveFailed,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final repo = ref.read(advisoryRepositoryProvider);
    final title = task.titleIn(lang) ?? taskTypeLabel(l10n, task.taskType);
    final instruction = task.instructionIn(lang);
    final late = task.overdueOn(today) && !task.done;
    final when = task.endDate != null && task.endDate != task.dueDate
        ? l10n.calendarDueBetween(
            formatDateIst(task.dueDate),
            formatDateIst(task.endDate!),
          )
        : l10n.calendarDueOn(formatDateIst(task.dueDate));
    return Card(
      key: Key('task-${task.id}'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  taskTypeIcon(task.taskType),
                  size: Tokens.space6,
                  color: task.done ? p.statusSuccess : p.primary,
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: app.text.heading),
                      Text(
                        taskTypeLabel(l10n, task.taskType),
                        style: app.text.caption.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (late)
                  Chip(
                    key: Key('task-late-${task.id}'),
                    avatar: Icon(
                      Icons.schedule,
                      size: Tokens.space4 + 2,
                      color: p.statusWarning,
                    ),
                    label: Text(
                      l10n.calendarLate,
                      style: app.text.label.copyWith(color: p.statusWarning),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space2),
            Text(when, style: app.text.body),
            if (instruction != null) ...<Widget>[
              const SizedBox(height: Tokens.space1),
              Text(instruction, style: app.text.body),
            ],
            AudioButton(
              promptId: 'task_${task.taskKey}',
              text: task.spokenIn(lang),
            ),
            const SizedBox(height: Tokens.space1),
            Wrap(
              spacing: Tokens.space2,
              runSpacing: Tokens.space1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FilterChip(
                  key: Key('task-done-${task.id}'),
                  avatar: Icon(
                    task.done
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: task.done ? p.statusSuccess : p.textSecondary,
                  ),
                  label: Text(
                    task.done ? l10n.calendarDone : l10n.calendarMarkDone,
                  ),
                  selected: task.done,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (value) async {
                    final r = await repo.setTaskDone(task, done: value);
                    if (context.mounted) await _report(context, r);
                  },
                ),
                FilterChip(
                  key: Key('task-reminder-${task.id}'),
                  avatar: Icon(
                    task.reminderEnabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    color: task.reminderEnabled ? p.primary : p.textSecondary,
                  ),
                  label: Text(
                    task.reminderEnabled
                        ? l10n.calendarRemindMe
                        : l10n.calendarReminderOff,
                  ),
                  selected: task.reminderEnabled,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (value) async {
                    final r = await repo.setTaskReminder(task, on: value);
                    if (context.mounted) await _report(context, r);
                  },
                ),
                if (task.pending)
                  Icon(
                    Icons.cloud_upload_outlined,
                    key: Key('task-queued-${task.id}'),
                    size: Tokens.space4 + 2,
                    color: p.textSecondary,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
