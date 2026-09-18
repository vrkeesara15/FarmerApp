import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'visit_copy.dart';

/// Status filter values of A34 (`null` = all).
const List<String?> _filters = <String?>[
  null,
  VisitStatuses.open,
  VisitStatuses.verified,
  VisitStatuses.partial,
  VisitStatuses.unverified,
];

/// A34 Visits list: Today / This week tabs, status filter, VisitCards with
/// their sync state, from the local table (works offline).
class VisitsListScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const VisitsListScreen({super.key});

  @override
  ConsumerState<VisitsListScreen> createState() => _VisitsListScreenState();
}

class _VisitsListScreenState extends ConsumerState<VisitsListScreen> {
  String? _status;

  String _filterLabel(CoreLocalizations l10n, String? s) => switch (s) {
    null => l10n.visitsFilterAll,
    VisitStatuses.open => l10n.visitStatusOpen,
    VisitStatuses.verified => l10n.visitVerified,
    VisitStatuses.partial => l10n.visitPartial,
    _ => l10n.visitUnverified,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final now = ref.watch(clockProvider)();
    final (dayFrom, dayTo) = istDayBounds(now);
    final weekFrom = dayFrom.subtract(const Duration(days: 6));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.visitsTitle),
          actions: <Widget>[
            SyncStatusPillLive(
              onTap: () => context.push(AppRoutes.syncDetails),
            ),
            const SizedBox(width: Tokens.space3),
          ],
          bottom: TabBar(
            labelStyle: context.app.text.label,
            tabs: <Widget>[
              Tab(
                key: const Key('visits-tab-today'),
                text: l10n.visitsTabToday,
              ),
              Tab(key: const Key('visits-tab-week'), text: l10n.visitsTabWeek),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('visits-start'),
          onPressed: () => context.push(VisitRoutes.start()),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(l10n.actionStartVisit),
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const OfflineBannerLive(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.spaceScreenPadding,
                  Tokens.space3,
                  Tokens.spaceScreenPadding,
                  Tokens.space1,
                ),
                child: Wrap(
                  spacing: Tokens.space2,
                  runSpacing: Tokens.space2,
                  children: <Widget>[
                    for (final s in _filters)
                      CropChip(
                        key: Key('visits-filter-${s ?? 'all'}'),
                        data: CropChipData(
                          name: _filterLabel(l10n, s),
                          icon: Icons.filter_list,
                        ),
                        selected: s == _status,
                        onTap: () => setState(() => _status = s),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _VisitList(
                      query: VisitListQuery(
                        from: dayFrom,
                        to: dayTo,
                        status: _status,
                      ),
                    ),
                    _VisitList(
                      query: VisitListQuery(
                        from: weekFrom,
                        to: dayTo,
                        status: _status,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisitList extends ConsumerWidget {
  const _VisitList({required this.query});

  final VisitListQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final rows = ref.watch(visitListProvider(query));
    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          ErrorState(onRetry: () => ref.invalidate(visitListProvider(query))),
      data: (list) => list.isEmpty
          ? EmptyState(
              key: const Key('visits-empty'),
              icon: Icons.place_outlined,
              title: l10n.visitsEmptyTitle,
              help: l10n.visitsEmptyHelp,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                Tokens.spaceScreenPadding,
                Tokens.space2,
                Tokens.spaceScreenPadding,
                Tokens.space12,
              ),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: Tokens.space2),
              itemBuilder: (context, i) => VisitSummaryCard(summary: list[i]),
            ),
    );
  }
}

/// A [VisitCard] for a [VisitSummary] (A34, A22 Visits tab).
class VisitSummaryCard extends ConsumerWidget {
  /// Creates the card.
  const VisitSummaryCard({required this.summary, super.key});

  /// The row.
  final VisitSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final p = context.app.palette;
    final v = summary.visit;
    final end = v.checkoutAt?.toUtc() ?? ref.read(clockProvider)();
    final duration = v.durationS != null
        ? Duration(seconds: v.durationS!)
        : end.difference(v.checkinAt.toUtc());
    return VisitCard(
      key: Key('visit-card-${v.id}'),
      farmerName: summary.farmerName,
      purpose: purposeOf(v.purpose),
      startedAtUtc: v.checkinAt.toUtc(),
      duration: duration.isNegative ? Duration.zero : duration,
      score: v.checkoutAt == null ? null : v.score,
      footnote: summary.failure != null
          ? l10n.visitCardFailed
          : summary.pendingSync
          ? l10n.visitCardPending
          : null,
      footnoteColor: summary.failure != null ? p.statusDanger : null,
      onTap: () => context.push(
        v.checkoutAt == null
            ? VisitRoutes.visit(v.id)
            : VisitRoutes.summary(v.id),
      ),
    );
  }
}
