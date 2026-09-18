import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../farmers/wizard_copy.dart';
import 'visit_copy.dart';

/// A33 Check-out summary (FA-017): the local expected VisitScoreBadge and
/// what was missing, replaced by the server-owned score / status /
/// components when the pull brings them (server wins). Under the minimum
/// duration is a warning, never a block.
class SummaryScreen extends ConsumerWidget {
  /// Creates the screen.
  const SummaryScreen({required this.visitId, super.key});

  /// Visit id.
  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final detail = ref.watch(visitDetailProvider(visitId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.visitSummaryTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: detail.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorState(
                  onRetry: () => ref.invalidate(visitDetailProvider(visitId)),
                ),
                data: (d) => d == null
                    ? EmptyState(title: l10n.visitsEmptyTitle)
                    : _Summary(detail: d),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.detail});

  final VisitDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final d = detail;
    final proof = d.proofAt(ref.read(clockProvider)());
    final items = proofItems(l10n, d, proof);
    final missing = items.where((i) => !i.satisfied).toList();
    final elapsed = d.visit.durationS != null
        ? Duration(seconds: d.visit.durationS!)
        : proof.elapsed;
    final underMinimum =
        d.flags.contains('under_minimum') ||
        (!d.serverScored && elapsed < proof.minDuration);
    final overridePending =
        d.geofenceResult == GeofenceResults.override &&
        d.visit.overrideApprovedBy == null;
    return VisitScroll(
      children: <Widget>[
        Text(d.farmer?.name ?? '', style: app.text.title),
        Text(
          '${purposeOf(d.visit.purpose).label(l10n)} · '
          '${formatDateTimeIst(d.visit.checkinAt)}',
          style: app.text.body.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: Tokens.space4),
        Center(
          child: Transform.scale(
            scale: 1.4,
            child: VisitScoreBadge(
              key: const Key('summary-score'),
              score: shownScore(d, proof),
            ),
          ),
        ),
        const SizedBox(height: Tokens.space3),
        Center(
          child: Text(
            d.serverScored ? l10n.visitSummaryServer : l10n.visitSummaryPending,
            key: Key(d.serverScored ? 'summary-server' : 'summary-expected'),
            textAlign: TextAlign.center,
            style: app.text.caption.copyWith(color: p.textSecondary),
          ),
        ),
        if (d.open) ...<Widget>[
          const SizedBox(height: Tokens.space3),
          VisitNotice(text: l10n.visitSummaryNotCheckedOut, tone: 'info'),
        ],
        const SizedBox(height: Tokens.space3),
        FactRow(
          label: l10n.visitSummaryDuration,
          value: l10n.visitDurationMinutes(elapsed.inMinutes),
          icon: Icons.timelapse_outlined,
        ),
        if (underMinimum) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          VisitNotice(
            key: const Key('summary-under-minimum'),
            text: l10n.visitUnderMinimum(proof.minDuration.inMinutes),
            tone: 'warning',
          ),
        ],
        if (overridePending) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          VisitNotice(text: l10n.visitSummaryOverridePending, tone: 'info'),
        ],
        SectionTitle(
          missing.isEmpty
              ? l10n.visitSummaryComplete
              : l10n.visitSummaryMissing,
        ),
        ProofChecklist(key: const Key('summary-proof'), items: items),
        if (!(d.serverComponents == null || !d.serverScored
            ? proof.integrityOk
            : (d.serverComponents!['integrity'] ?? 0) > 0))
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Text(
              l10n.proofIntegrityIssue,
              style: app.text.caption.copyWith(color: p.statusWarning),
            ),
          ),
        const SizedBox(height: Tokens.space6),
        AppButton(
          key: const Key('summary-done'),
          label: l10n.visitDone,
          icon: Icons.check,
          onPressed: () => context.go(VisitRoutes.list),
        ),
      ],
    );
  }
}
