import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/commerce_copy.dart';

/// Localised label of an overdue bucket.
String bucketLabel(CoreLocalizations l10n, OverdueBucket b) => switch (b) {
  OverdueBucket.d0to30 => l10n.khataBucket0to30,
  OverdueBucket.d31to60 => l10n.khataBucket31to60,
  OverdueBucket.d61to90 => l10n.khataBucket61to90,
  OverdueBucket.d90plus => l10n.khataBucket90plus,
};

/// A58 Khata for a farmer (FA-022) as a full screen.
class KhataScreen extends ConsumerWidget {
  /// Creates the screen.
  const KhataScreen({required this.farmerId, super.key});

  /// Farmer.
  final String farmerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final name = farmerNameOf(ref, farmerId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          name.isEmpty ? l10n.khataTitle : '${l10n.khataTitle} · $name',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(child: KhataBody(farmerId: farmerId)),
          ],
        ),
      ),
    );
  }
}

/// A58 content (also the A22 Khata tab): balance header (the sum of the
/// entries shown), overdue bucket chips, due dates with the harvest month,
/// debit / credit entries, payment history, collections not yet on the
/// khata, and Collect → A52 in dues mode. Cached for offline viewing with
/// its "as of" time.
class KhataBody extends ConsumerStatefulWidget {
  /// Creates the body.
  const KhataBody({required this.farmerId, super.key});

  /// Farmer.
  final String farmerId;

  @override
  ConsumerState<KhataBody> createState() => _KhataBodyState();
}

class _KhataBodyState extends ConsumerState<KhataBody> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    final online = await ref.read(connectivityMonitorProvider).isOnline();
    if (!online || !mounted) return;
    setState(() => _loading = true);
    await ref.read(khataRepositoryProvider).refresh(widget.farmerId);
    if (mounted) setState(() => _loading = false);
  }

  String _entryText(CoreLocalizations l10n, KhataLine e) =>
      e.note?.isNotEmpty ?? false
      ? e.note!
      : switch (e.refType) {
          'order' => l10n.khataEntryOrder,
          'payment' => l10n.khataEntryPayment,
          _ => l10n.khataEntryAdjustment,
        };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final offline = ref.watch(offlineProvider);
    final now = ref.watch(clockProvider)();
    final khata = ref.watch(khataProvider(widget.farmerId));
    final pending =
        (ref.watch(collectionsProvider(CollectionsRange.week)).value?.items ??
                const <PaymentView>[])
            .where(
              (v) =>
                  v.payment.farmerId == widget.farmerId &&
                  v.payment.orderId == null &&
                  (v.state == CollectionState.waitingToSync ||
                      v.state == CollectionState.pendingReconciliation),
            )
            .toList(growable: false);
    return khata.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Tokens.spaceScreenPadding),
        child: Skeletons.list(),
      ),
      error: (e, _) => ErrorState(onRetry: _refresh),
      data: (k) {
        if (k == null) {
          return Center(
            child: _loading
                ? const CircularProgressIndicator()
                : EmptyState(
                    key: const Key('khata-not-loaded'),
                    icon: Icons.account_balance_wallet_outlined,
                    title: l10n.khataNotLoaded,
                    help: l10n.khataNotLoadedHelp,
                    actionLabel: offline ? null : l10n.catalogRefresh,
                    onAction: offline ? null : _refresh,
                  ),
          );
        }
        final balance = k.displayedBalancePaise;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            key: const Key('khata-body'),
            padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    offline ? Icons.cloud_off_outlined : Icons.schedule,
                    size: Tokens.space4,
                    color: offline ? p.statusWarning : p.textSecondary,
                  ),
                  const SizedBox(width: Tokens.space1),
                  Expanded(
                    child: Text(
                      offline
                          ? l10n.khataOfflineAsOf(formatDateTimeIst(k.asOf))
                          : l10n.khataAsOf(formatDateTimeIst(k.asOf)),
                      key: const Key('khata-as-of'),
                      style: app.text.caption.copyWith(
                        color: offline ? p.statusWarning : p.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space2),
              KhataLedger(
                key: const Key('khata-ledger'),
                balancePaise: balance,
                dueDateUtc: k.nextDueDate,
                now: now,
                actionLabel: l10n.khataCollect,
                onAction: balance > 0
                    ? () =>
                          context.push(CommerceRoutes.collect(widget.farmerId))
                    : null,
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (k.overduePaise > 0)
                      Text(
                        l10n.khataOverdue(formatInr(k.overduePaise)),
                        key: const Key('khata-overdue'),
                        style: app.text.heading.copyWith(color: p.statusDanger),
                      ),
                    const SizedBox(height: Tokens.space2),
                    Wrap(
                      spacing: Tokens.space2,
                      runSpacing: Tokens.space2,
                      children: <Widget>[
                        for (final b in OverdueBucket.values)
                          StatusPill(
                            key: Key('khata-bucket-${b.wire}'),
                            text:
                                '${bucketLabel(l10n, b)}: '
                                '${formatInr(k.buckets[b] ?? 0, showPaise: false)}',
                            color: (k.buckets[b] ?? 0) > 0
                                ? p.statusDanger
                                : p.textSecondary,
                          ),
                      ],
                    ),
                  ],
                ),
                entries: <KhataEntry>[
                  for (final e in k.entries)
                    KhataEntry(
                      dateUtc: e.createdAt,
                      description: _entryText(l10n, e),
                      amountPaise: e.amountPaise,
                      isCredit: !e.isDebit,
                      dueDateUtc: e.isDebit ? e.dueDate : null,
                      harvestMonthUtc: e.isDebit ? e.harvestMonth : null,
                    ),
                ],
              ),
              if (pending.isNotEmpty) ...<Widget>[
                const SizedBox(height: Tokens.space4),
                Text(l10n.khataPendingCollections, style: app.text.heading),
                for (final v in pending)
                  ListTile(
                    key: Key('khata-pending-${v.payment.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.hourglass_top),
                    title: Text(modeLabel(l10n, v.payment.mode)),
                    subtitle: Text(collectionStateLabel(l10n, v.state)),
                    trailing: Text(
                      formatInr(v.payment.amountPaise),
                      style: app.text.heading,
                    ),
                  ),
              ],
              const SizedBox(height: Tokens.space4),
              Text(l10n.khataPaymentHistory, style: app.text.heading),
              if (k.payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
                  child: Text(
                    l10n.khataNoPayments,
                    style: app.text.body.copyWith(color: p.textSecondary),
                  ),
                ),
              for (final pay in k.payments)
                ListTile(
                  key: Key('khata-payment-${pay.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(modeLabel(l10n, pay.mode)),
                  subtitle: Text(
                    formatDateIst(pay.paidAt ?? pay.createdAt ?? k.asOf),
                  ),
                  trailing: Text(
                    formatInr(pay.amountPaise),
                    style: app.text.heading,
                  ),
                ),
              const SizedBox(height: Tokens.space6),
            ],
          ),
        );
      },
    );
  }
}
