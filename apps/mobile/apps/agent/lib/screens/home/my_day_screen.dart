import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A12 My day timeline shell (VV-007 client side): today's sessions, the
/// track on a map, km (client estimate), pending / accepted points. Gaps
/// and reasons are VV-008 (P1) and stay an EmptyState.
class MyDayScreen extends ConsumerWidget {
  /// Creates the screen.
  const MyDayScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final day = ref.watch(myDayProvider);
    final tiles = ref.watch(mapTileProviderProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myDayTitle)),
      body: SafeArea(
        child: day.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.refresh(myDayProvider)),
          data: (d) => d.isEmpty
              ? EmptyState(
                  key: const Key('my-day-empty'),
                  icon: Icons.timeline_outlined,
                  title: l10n.myDayEmpty,
                  help: l10n.myDayEmptyHelp,
                )
              : ListView(
                  padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                  children: <Widget>[
                    if (d.track.length >= 2)
                      MapPanel(
                        boundary: d.track,
                        closed: false,
                        showCorners: false,
                        interactive: false,
                        tileProvider: tiles,
                        height: 200,
                      ),
                    if (d.track.length >= 2)
                      const SizedBox(height: Tokens.space3),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(
                            value: _km(d.distanceM),
                            label: l10n.myDayKm(''),
                            icon: Icons.route_outlined,
                          ),
                        ),
                        const SizedBox(width: Tokens.space2),
                        Expanded(
                          child: StatTile(
                            value: formatIndianDigits(d.pointsPending),
                            label: l10n.syncPending(d.pointsPending),
                            icon: Icons.cloud_upload_outlined,
                          ),
                        ),
                        const SizedBox(width: Tokens.space2),
                        Expanded(
                          child: StatTile(
                            value: formatIndianDigits(d.pointsAccepted),
                            label: l10n.syncSynced,
                            icon: Icons.cloud_done_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.space4),
                    for (final s in d.sessions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Tokens.space3),
                        child: Material(
                          key: Key('day-session-${s.session.id}'),
                          color: s.active
                              ? app.tint(p.statusSuccessContainer)
                              : p.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              Tokens.radiusCard,
                            ),
                            side: BorderSide(
                              color: s.active ? p.statusSuccess : p.border,
                              width: app.borderWidth,
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              s.active
                                  ? Icons.work_outline
                                  : Icons.work_off_outlined,
                              color: s.active
                                  ? p.statusSuccess
                                  : p.textSecondary,
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
                      ),
                    Material(
                      color: p.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.radiusCard),
                        side: app.borderSide,
                      ),
                      child: EmptyState(
                        key: const Key('my-day-gaps'),
                        icon: Icons.linear_scale_outlined,
                        title: l10n.myDayGapsTitle,
                        help: l10n.myDayGapsHelp,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
