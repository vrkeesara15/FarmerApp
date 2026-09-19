import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/kisan_widgets.dart';
import '../../widgets/upi_pay.dart';
import 'shop_state.dart';

/// F33 Order tracking (FM-010): placed → packed → ready → collected with
/// times, items, total and how it is paid; "Pay by UPI" while unpaid.
/// Cached for offline viewing with "as of".
class OrderTrackingScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const OrderTrackingScreen({required this.orderId, super.key});

  /// Order shown.
  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(kisanRepositoryProvider).refreshOrder(widget.orderId));
  }

  Future<void> _pay() async {
    final l10n = CoreLocalizations.of(context);
    final result = await payByUpi(context, ref, <String, Object?>{
      'order_id': widget.orderId,
    });
    await ref.read(kisanRepositoryProvider).refreshOrder(widget.orderId);
    if (!mounted) return;
    showKisanMessage(context, switch (result.outcome) {
      UpiOutcome.paid => l10n.kisanPaidThanks,
      UpiOutcome.offline => l10n.kisanNeedsInternet,
      _ => l10n.kisanNotPaidYet,
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final cached = ref.watch(kisanOrderProvider(widget.orderId));
    final steps = <String>[
      l10n.orderStatusPlaced,
      l10n.orderStatusPacked,
      l10n.orderStatusReady,
      l10n.kisanOrderCollected,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanOrderTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: cached.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const ErrorState(),
                data: (c) {
                  if (c == null) {
                    return EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: l10n.kisanOrderNotSaved,
                      help: l10n.kisanNeedsInternet,
                    );
                  }
                  final o = c.value;
                  final unpaid = !o.paid && !o.onCredit && o.step >= 0;
                  return RefreshIndicator(
                    onRefresh: () => ref
                        .read(kisanRepositoryProvider)
                        .refreshOrder(widget.orderId),
                    child: ListView(
                      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                      children: <Widget>[
                        Text(
                          orderStatusLabel(l10n, o.status),
                          key: const Key('order-status'),
                          style: app.text.title,
                        ),
                        if (o.placedAt != null)
                          Text(
                            l10n.kisanPlacedOn(formatDateTimeIst(o.placedAt!)),
                            style: app.text.body.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        const SizedBox(height: Tokens.space4),
                        if (o.step >= 0)
                          StageTimeline(
                            key: const Key('order-timeline'),
                            stages: steps,
                            currentIndex: o.step,
                          )
                        else
                          Text(
                            l10n.orderStatusCancelled,
                            style: app.text.heading.copyWith(
                              color: p.statusDanger,
                            ),
                          ),
                        const SizedBox(height: Tokens.space2),
                        for (var i = 0; i <= o.step && i < 4; i++)
                          if (o.reachedAt(i) case final at?)
                            Text(
                              '${steps[i]} · ${formatDateTimeIst(at)}',
                              style: app.text.caption,
                            ),
                        const SizedBox(height: Tokens.space4),
                        KisanCard(
                          title: l10n.kisanItems,
                          icon: Icons.inventory_2_outlined,
                          child: Column(
                            children: <Widget>[
                              for (final l in o.lines)
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        '${l.name ?? l10n.kisanProductTitle}'
                                        '${l.pack == null || l.pack!.isEmpty ? '' : ' · ${l.pack}'}'
                                        ' × ${l.qty.toStringAsFixed(0)}',
                                        style: app.text.body,
                                      ),
                                    ),
                                    Text(
                                      formatInr(l.lineTotalPaise),
                                      style: app.text.body,
                                    ),
                                  ],
                                ),
                              const Divider(),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      l10n.orderTotal,
                                      style: app.text.heading,
                                    ),
                                  ),
                                  Text(
                                    formatInr(o.totalPaise),
                                    key: const Key('order-total'),
                                    style: app.text.heading,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Tokens.space2),
                        Row(
                          children: <Widget>[
                            Icon(
                              o.paid
                                  ? Icons.check_circle
                                  : o.onCredit
                                  ? Icons.menu_book_outlined
                                  : Icons.storefront_outlined,
                              color: o.paid ? p.statusSuccess : p.primary,
                            ),
                            const SizedBox(width: Tokens.space2),
                            Expanded(
                              child: Text(
                                o.paid
                                    ? l10n.kisanOrderPaid
                                    : o.onCredit
                                    ? l10n.kisanOrderOnKhata
                                    : l10n.kisanPayAtStoreNote,
                                key: const Key('order-payment'),
                                style: app.text.body,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Tokens.space3),
                        AsOfLabel(c.asOf),
                        if (unpaid) ...<Widget>[
                          const SizedBox(height: Tokens.space4),
                          AppButton(
                            key: const Key('order-pay-upi'),
                            label: l10n.kisanPayUpi,
                            icon: Icons.qr_code_2,
                            onPressed: _pay,
                          ),
                        ],
                      ],
                    ),
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
