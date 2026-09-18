import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/commerce_copy.dart';

/// A59 Collections list (FA-021): today's and this week's payments the
/// officer collected, with mode, status (pending reconciliation / paid /
/// failed ...) and totals by mode.
class CollectionsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  CollectionsRange _range = CollectionsRange.today;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final summary = ref.watch(collectionsProvider(_range));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.collectionsTitle),
        actions: <Widget>[
          SyncStatusPillLive(onTap: () => context.push('/settings/sync')),
          const SizedBox(width: Tokens.space3),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Padding(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              child: SegmentedButton<CollectionsRange>(
                key: const Key('collections-range'),
                segments: <ButtonSegment<CollectionsRange>>[
                  ButtonSegment<CollectionsRange>(
                    value: CollectionsRange.today,
                    label: Text(l10n.collectionsToday),
                  ),
                  ButtonSegment<CollectionsRange>(
                    value: CollectionsRange.week,
                    label: Text(l10n.collectionsWeek),
                  ),
                ],
                selected: <CollectionsRange>{_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
            ),
            Expanded(
              child: summary.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Tokens.spaceScreenPadding),
                  child: Skeletons.list(),
                ),
                error: (e, _) => ErrorState(
                  onRetry: () => ref.invalidate(collectionsProvider(_range)),
                ),
                data: (s) {
                  if (s.items.isEmpty) {
                    return Center(
                      child: EmptyState(
                        key: const Key('collections-empty'),
                        icon: Icons.payments_outlined,
                        title: l10n.collectionsEmpty,
                        help: l10n.collectionsEmptyHelp,
                      ),
                    );
                  }
                  return ListView(
                    key: const Key('collections-list'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.spaceScreenPadding,
                    ),
                    children: <Widget>[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(Tokens.space3),
                          child: Column(
                            children: <Widget>[
                              for (final mode in <String>[
                                PaymentModes.cash,
                                PaymentModes.upiQr,
                                PaymentModes.paymentLink,
                                PaymentModes.credit,
                              ])
                                if (s.totalsByMode.containsKey(mode))
                                  MoneyRow(
                                    key: Key('collections-total-$mode'),
                                    label: modeLabel(l10n, mode),
                                    paise: s.totalsByMode[mode]!,
                                  ),
                              const Divider(),
                              MoneyRow(
                                key: const Key('collections-total'),
                                label: l10n.collectionsTotal,
                                paise: s.collectedPaise,
                                strong: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: Tokens.space3),
                      for (final v in s.items)
                        ListTile(
                          key: Key('collection-${v.payment.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(switch (v.payment.mode) {
                            PaymentModes.upiQr => Icons.qr_code_2,
                            PaymentModes.paymentLink => Icons.link,
                            PaymentModes.credit => Icons.menu_book_outlined,
                            _ => Icons.payments_outlined,
                          }, color: p.textSecondary),
                          title: Text(
                            <String>[
                              farmerNameOf(ref, v.payment.farmerId),
                              modeLabel(l10n, v.payment.mode),
                            ].where((t) => t.isNotEmpty).join(' · '),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: Tokens.space1),
                            child: Wrap(
                              spacing: Tokens.space2,
                              runSpacing: Tokens.space1,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                StatusPill(
                                  text: collectionStateLabel(l10n, v.state),
                                  color: collectionStateColor(p, v.state),
                                ),
                                Text(
                                  formatTimeIst(v.payment.collectedAt),
                                  style: app.text.caption,
                                ),
                              ],
                            ),
                          ),
                          trailing: Text(
                            formatInr(v.payment.amountPaise),
                            style: app.text.heading,
                          ),
                          onTap: v.payment.orderId == null
                              ? null
                              : () => context.push(
                                  CommerceRoutes.order(v.payment.orderId!),
                                ),
                        ),
                      const SizedBox(height: Tokens.space6),
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
