import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'field_widgets.dart';

/// A60 My performance (FA-024): this month's targets against the actuals,
/// the incentive earned so far and a verified-visit trend.
///
/// The numbers come from `GET /v1/me/performance` (equal by construction to
/// the console's officer profile) with the month's targets from
/// `GET /v1/targets`; both are cached, so the screen opens offline with an
/// "as of" line. The trend bars are counted from this device's own synced
/// `visits` rows, which needs no extra endpoint.
class PerformanceScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PerformanceScreen({super.key});

  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  @override
  void initState() {
    super.initState();
    final (from, to) = istMonthBounds(ref.read(clockProvider)());
    unawaited(
      ref.read(fieldRepositoryProvider).refreshPerformance(from: from, to: to),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final cached = ref.watch(performanceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.performanceTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: cached.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorState(
                  onRetry: () => ref.invalidate(performanceProvider),
                ),
                data: (view) {
                  final perf = view.value;
                  if (perf == null) {
                    return EmptyState(
                      key: const Key('performance-empty'),
                      icon: Icons.insights_outlined,
                      title: l10n.perfEmpty,
                      help: l10n.perfEmptyHelp,
                    );
                  }
                  final t = perf.targets;
                  return ListView(
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    children: <Widget>[
                      if (view.asOf != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FieldCaption(
                            l10n.fieldAsOf(formatDateTimeIst(view.asOf!)),
                            icon: Icons.schedule,
                          ),
                        ),
                      const SizedBox(height: Tokens.space2),
                      Text(l10n.perfTargetsVsActual, style: app.text.heading),
                      FieldCard(
                        child: Padding(
                          padding: const EdgeInsets.all(Tokens.space3),
                          child: Column(
                            children: <Widget>[
                              TargetRow(
                                key: const Key('perf-verified-visits'),
                                label: l10n.statVisitsVerified,
                                actual: perf.verifiedVisits,
                                actualText: formatIndianDigits(
                                  perf.verifiedVisits,
                                ),
                                target: t?.visitsVerified,
                                targetText: t?.visitsVerified == null
                                    ? null
                                    : formatIndianDigits(t!.visitsVerified!),
                              ),
                              TargetRow(
                                key: const Key('perf-new-farmers'),
                                label: l10n.perfNewFarmers,
                                actual: perf.farmersAdded,
                                actualText: formatIndianDigits(
                                  perf.farmersAdded,
                                ),
                                target: t?.newFarmers,
                                targetText: t?.newFarmers == null
                                    ? null
                                    : formatIndianDigits(t!.newFarmers!),
                              ),
                              TargetRow(
                                key: const Key('perf-sales'),
                                label: l10n.perfSales,
                                actual: perf.salesNetPaise,
                                actualText: formatInr(
                                  perf.salesNetPaise,
                                  showPaise: false,
                                ),
                                target: t?.salesPaise,
                                targetText: t?.salesPaise == null
                                    ? null
                                    : formatInr(
                                        t!.salesPaise!,
                                        showPaise: false,
                                      ),
                              ),
                              TargetRow(
                                key: const Key('perf-collections'),
                                label: l10n.statCollections,
                                actual: perf.collectionsPaise,
                                actualText: formatInr(
                                  perf.collectionsPaise,
                                  showPaise: false,
                                ),
                                target: t?.collectionsPaise,
                                targetText: t?.collectionsPaise == null
                                    ? null
                                    : formatInr(
                                        t!.collectionsPaise!,
                                        showPaise: false,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      FieldCard(
                        key: const Key('perf-incentive'),
                        color: app.tint(p.primaryContainer),
                        child: ListTile(
                          leading: Icon(
                            Icons.emoji_events_outlined,
                            color: p.primary,
                          ),
                          title: Text(
                            l10n.perfIncentive,
                            style: app.text.label,
                          ),
                          subtitle: Text(
                            perf.incentiveEarnedPaise == null
                                ? l10n.perfIncentivePending
                                : formatInr(perf.incentiveEarnedPaise!),
                            style: app.text.body,
                          ),
                        ),
                      ),
                      Text(l10n.perfTrendTitle, style: app.text.heading),
                      FieldCard(
                        key: const Key('perf-trend'),
                        child: Padding(
                          padding: const EdgeInsets.all(Tokens.space3),
                          child: Sparkline(values: perf.trend),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: StatTile(
                              value: perf.confirmationRate == null
                                  ? '—'
                                  : '${(perf.confirmationRate! * 100).round()}%',
                              label: l10n.perfConfirmationRate,
                              icon: Icons.verified_user_outlined,
                            ),
                          ),
                          const SizedBox(width: Tokens.space2),
                          Expanded(
                            child: StatTile(
                              value: formatIndianDigits(perf.rank),
                              label: l10n.perfRank(perf.rank),
                              icon: Icons.leaderboard_outlined,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
