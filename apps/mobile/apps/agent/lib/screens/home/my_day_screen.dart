import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../field/field_widgets.dart';

/// A12 My day timeline (VV-007 client side, VV-008).
///
/// The map, the sessions and the km estimate come from this phone's own
/// duty rows, so the screen works with no network at all. When
/// `GET /v1/me/day` has been pulled *and every duty session of the day has
/// been through the server's track processing* (VV-006:
/// `DayTimeline.processed`), the server's km, stops, gaps and visit pins
/// replace the estimate, and the caption under the tiles says which of the
/// two the officer is looking at. Until then the phone's own figure stands
/// — the server's own haversine fallback for an unprocessed session is not
/// better than this phone's, and calling it "processed" would be a lie the
/// officer's travel allowance is later measured against.
///
/// Every gap without a reason gets an "add reason" sheet whose answer is
/// queued through the outbox (`track_gap`).
class MyDayScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MyDayScreen({super.key});

  @override
  ConsumerState<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends ConsumerState<MyDayScreen> {
  @override
  void initState() {
    super.initState();
    final date = ref.read(todayIstProvider);
    unawaited(ref.read(fieldRepositoryProvider).refreshDay(date));
  }

  static String _km(double metres) => (metres / 1000).toStringAsFixed(1);

  String _endReason(CoreLocalizations l10n, DutySession s) =>
      switch (DutyEndReason.parse(s.endReason)) {
        DutyEndReason.manual => l10n.myDayEndReasonManual,
        DutyEndReason.autoTime => l10n.myDayEndReasonAutoTime,
        DutyEndReason.autoIdle => l10n.myDayEndReasonAutoIdle,
        DutyEndReason.forced => l10n.myDayEndReasonForced,
        DutyEndReason.rejected => l10n.myDayEndReasonRejected,
        null => '',
      };

  Future<void> _addReason(DayGap gap) async {
    final result = await showModalBottomSheet<(GapReason, String)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => GapReasonSheet(gap: gap),
    );
    if (result == null || !mounted) return;
    await ref
        .read(fieldRepositoryProvider)
        .setGapReason(gap.id, result.$1, note: result.$2);
    if (!mounted) return;
    final l10n = CoreLocalizations.of(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.myDayGapReasonSaved)));
  }

  String _reasonLabel(CoreLocalizations l10n, GapReason reason) =>
      switch (reason) {
        GapReason.network => l10n.myDayGapReasonNetwork,
        GapReason.personalBreak => l10n.myDayGapReasonBreak,
        GapReason.vehicle => l10n.myDayGapReasonVehicle,
        GapReason.other => l10n.myDayGapReasonOther,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final day = ref.watch(myDayProvider);
    final date = ref.watch(todayIstProvider);
    final server = ref.watch(dayTimelineProvider(date)).value;
    final timeline = server?.value;
    // VV-006: the server's figures only once it has actually processed the
    // day (every session ended and carrying a processed km).
    final processed = timeline?.processed ?? false;
    final tiles = ref.watch(mapTileProviderProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myDayTitle)),
      body: SafeArea(
        child: day.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(myDayProvider)),
          data: (d) => d.isEmpty && (timeline == null || timeline.track.isEmpty)
              ? EmptyState(
                  key: const Key('my-day-empty'),
                  icon: Icons.timeline_outlined,
                  title: l10n.myDayEmpty,
                  help: l10n.myDayEmptyHelp,
                )
              : ListView(
                  padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                  children: <Widget>[
                    if ((timeline?.track ?? d.track).length >= 2) ...<Widget>[
                      MapPanel(
                        key: const Key('my-day-map'),
                        boundary: timeline?.track.isNotEmpty ?? false
                            ? timeline!.track
                            : d.track,
                        closed: false,
                        showCorners: false,
                        interactive: false,
                        tileProvider: tiles,
                        height: 200,
                      ),
                      const SizedBox(height: Tokens.space3),
                    ],
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(
                            key: const Key('my-day-km'),
                            value: processed
                                ? timeline!.km.toStringAsFixed(1)
                                : _km(d.distanceM),
                            label: l10n.myDayKm(''),
                            icon: Icons.route_outlined,
                          ),
                        ),
                        const SizedBox(width: Tokens.space2),
                        Expanded(
                          child: StatTile(
                            key: const Key('my-day-stops'),
                            value: formatIndianDigits(
                              timeline?.stops.length ?? 0,
                            ),
                            label: l10n.myDayStops(timeline?.stops.length ?? 0),
                            icon: Icons.pause_circle_outline,
                          ),
                        ),
                        const SizedBox(width: Tokens.space2),
                        Expanded(
                          child: StatTile(
                            value: formatIndianDigits(
                              timeline?.visits.length ?? 0,
                            ),
                            label: l10n.myDayVisitPins(
                              timeline?.visits.length ?? 0,
                            ),
                            icon: Icons.place_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.space2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FieldCaption(
                        key: const Key('my-day-km-source'),
                        processed
                            ? l10n.myDayKmProcessed
                            : l10n.myDayKmEstimated,
                        icon: Icons.info_outline,
                      ),
                    ),
                    const SizedBox(height: Tokens.space2),
                    Row(
                      children: <Widget>[
                        FieldCaption(
                          l10n.syncPending(d.pointsPending),
                          icon: Icons.cloud_upload_outlined,
                        ),
                        const SizedBox(width: Tokens.space3),
                        FieldCaption(
                          l10n.syncSynced,
                          icon: Icons.cloud_done_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.space4),
                    for (final s in d.sessions)
                      FieldCard(
                        key: Key('day-session-${s.session.id}'),
                        color: s.active
                            ? app.tint(p.statusSuccessContainer)
                            : p.surface,
                        borderColor: s.active ? p.statusSuccess : null,
                        child: ListTile(
                          leading: Icon(
                            s.active
                                ? Icons.work_outline
                                : Icons.work_off_outlined,
                            color: s.active ? p.statusSuccess : p.textSecondary,
                          ),
                          title: Text(
                            s.active
                                ? l10n.myDaySessionActive(
                                    formatTimeIst(s.session.startAt),
                                  )
                                : l10n.myDaySession(
                                    formatTimeIst(s.session.startAt),
                                    formatTimeIst(s.session.endAt!),
                                  ),
                            style: app.text.label,
                          ),
                          subtitle: Text(
                            <String>[
                              l10n.myDayKm(_km(s.distanceM)),
                              l10n.myDayPoints(
                                s.pointsPending,
                                s.pointsAccepted,
                              ),
                              if (!s.active) _endReason(l10n, s.session),
                            ].join(' · '),
                            style: app.text.caption.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: Tokens.space2),
                    Text(l10n.myDayGapsTitle, style: app.text.heading),
                    const SizedBox(height: Tokens.space1),
                    FieldCaption(
                      l10n.myDayManagerSeesReasons,
                      icon: Icons.visibility_outlined,
                    ),
                    const SizedBox(height: Tokens.space2),
                    if (timeline == null || timeline.gaps.isEmpty)
                      FieldCard(
                        child: EmptyState(
                          key: const Key('my-day-gaps'),
                          icon: Icons.linear_scale_outlined,
                          title: l10n.myDayNoGaps,
                          help: l10n.myDayGapsHelp,
                        ),
                      )
                    else
                      for (final gap in timeline.gaps)
                        FieldCard(
                          key: Key('day-gap-${gap.id}'),
                          borderColor: gap.needsReason ? p.statusWarning : null,
                          child: ListTile(
                            leading: Icon(
                              Icons.linear_scale_outlined,
                              color: gap.needsReason
                                  ? p.statusWarning
                                  : p.textSecondary,
                            ),
                            title: Text(
                              l10n.myDayGapRange(
                                formatTimeIst(gap.start),
                                formatTimeIst(gap.end),
                                (gap.durationS / 60).round(),
                              ),
                              style: app.text.label,
                            ),
                            subtitle: gap.reason == null
                                ? null
                                : Text(
                                    <String>[
                                      _reasonLabel(l10n, gap.reason!),
                                      if (gap.note != null &&
                                          gap.note!.isNotEmpty)
                                        gap.note!,
                                    ].join(' · '),
                                    style: app.text.body,
                                  ),
                            trailing: gap.needsReason
                                ? AppButton(
                                    key: Key('day-gap-reason-${gap.id}'),
                                    label: l10n.myDayGapAddReason,
                                    variant: AppButtonVariant.tertiary,
                                    size: AppButtonSize.medium,
                                    expand: false,
                                    onPressed: () => unawaited(_addReason(gap)),
                                  )
                                : Icon(
                                    Icons.check_circle_outline,
                                    color: p.statusSuccess,
                                  ),
                          ),
                        ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// VV-008 "add a reason" sheet: four reasons plus a free-text note with
/// FA-005 voice input.
class GapReasonSheet extends StatefulWidget {
  /// Creates the sheet.
  const GapReasonSheet({required this.gap, super.key});

  /// The gap being explained.
  final DayGap gap;

  @override
  State<GapReasonSheet> createState() => _GapReasonSheetState();
}

class _GapReasonSheetState extends State<GapReasonSheet> {
  final TextEditingController _note = TextEditingController();
  GapReason _reason = GapReason.network;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    String label(GapReason r) => switch (r) {
      GapReason.network => l10n.myDayGapReasonNetwork,
      GapReason.personalBreak => l10n.myDayGapReasonBreak,
      GapReason.vehicle => l10n.myDayGapReasonVehicle,
      GapReason.other => l10n.myDayGapReasonOther,
    };
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.spaceScreenPadding,
        right: Tokens.spaceScreenPadding,
        top: Tokens.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.myDayGapSheetTitle, style: app.text.heading),
          const SizedBox(height: Tokens.space1),
          FieldCaption(
            l10n.myDayGapRange(
              formatTimeIst(widget.gap.start),
              formatTimeIst(widget.gap.end),
              (widget.gap.durationS / 60).round(),
            ),
          ),
          const SizedBox(height: Tokens.space3),
          RadioGroup<GapReason>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v ?? _reason),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final r in GapReason.values)
                  RadioListTile<GapReason>(
                    key: Key('gap-reason-${r.wire}'),
                    value: r,
                    title: Text(label(r), style: app.text.body),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.space2),
          VoiceTextField(
            label: l10n.myDayGapNoteLabel,
            hintText: l10n.myDayGapNoteHint,
            controller: _note,
            maxLines: 2,
            fieldKey: const Key('gap-note'),
            micKey: const Key('gap-note-mic'),
          ),
          const SizedBox(height: Tokens.space3),
          AppButton(
            key: const Key('gap-save'),
            label: l10n.actionDone,
            onPressed: () =>
                Navigator.of(context).pop((_reason, _note.text.trim())),
          ),
        ],
      ),
    );
  }
}
