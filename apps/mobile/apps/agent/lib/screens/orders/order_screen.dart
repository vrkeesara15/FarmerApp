import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'commerce_copy.dart';

/// A57 Order success / detail (FA-020): summary (server totals once the
/// order synced, else the estimate), status timeline placed → reserved →
/// packed → ready → handed over / delivered from pulls, payments, and
/// "Share invoice on WhatsApp" once an invoice exists (online only). A
/// rejected order explains why (`insufficient_stock` per line,
/// `sku_not_recommendable`) and offers "Edit and send again".
class OrderScreen extends ConsumerWidget {
  /// Creates the screen.
  const OrderScreen({required this.orderId, super.key});

  /// Order id.
  final String orderId;

  Future<void> _share(BuildContext context, WidgetRef ref, OrderRow o) async {
    final l10n = CoreLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final out = await ref.read(paymentsApiProvider).invoicePdf(o.invoiceId!);
    final url = out.body['url'] as String?;
    if (out.result != PaymentCallResult.ok || url == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.orderShareFailed)));
      return;
    }
    await ref
        .read(invoiceSharerProvider)
        .share(
          l10n.orderShareText(o.invoiceNo ?? '', url),
          subject: l10n.orderInvoiceNo(o.invoiceNo ?? ''),
        );
  }

  void _edit(BuildContext context, WidgetRef ref, OrderView v) {
    final cache = ref.read(catalogCacheProvider);
    unawaited(() async {
      final lines = <CartLine>[];
      for (final l in v.lines) {
        final item =
            await cache.item(l.skuId, storeId: v.order.storeId) ??
            CatalogItem(
              productId: '',
              skuId: l.skuId,
              name: l.productName,
              brand: '',
              ownBrand: false,
              category: CatalogCategory.other,
              packLabel: l.packLabel,
              mrpPaise: l.estimatedUnitPricePaise,
              pricePaise: l.estimatedUnitPricePaise,
            );
        lines.add(CartLine(item: item, qty: l.qty.round()));
      }
      ref
          .read(cartProvider.notifier)
          .editRejected(
            orderId: v.order.id,
            farmerId: v.order.farmerId ?? '',
            storeId: v.order.storeId,
            lines: lines,
            fulfilment: Fulfilment.parse(v.order.fulfilment),
            shortfalls: v.shortfalls,
          );
      if (context.mounted) await context.push(CommerceRoutes.cart);
    }());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final view = ref.watch(orderViewProvider(orderId));
    return view.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.orderTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(l10n.orderTitle)),
        body: ErrorState(
          onRetry: () => ref.invalidate(orderViewProvider(orderId)),
        ),
      ),
      data: (v) => v == null
          ? Scaffold(
              appBar: AppBar(title: Text(l10n.orderTitle)),
              body: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: l10n.ordersEmpty,
              ),
            )
          : _body(context, ref, v),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, OrderView v) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final o = v.order;
    final offline = ref.watch(offlineProvider);
    final payments =
        ref.watch(orderPaymentsProvider(orderId)).value ??
        const <PaymentView>[];
    final paid = payments.any((x) => x.state.counts);
    final rejected = v.rejection != null;
    final (IconData icon, Color color, String title) = rejected
        ? (Icons.error_outline, p.statusDanger, l10n.orderRejectedTitle)
        : v.pendingSync
        ? (Icons.cloud_upload_outlined, p.statusInfo, l10n.orderQueuedTitle)
        : (Icons.check_circle_outline, p.statusSuccess, l10n.orderPlacedTitle);
    final shareReason = o.invoiceId == null
        ? l10n.orderShareNoInvoice
        : offline
        ? l10n.orderShareOffline
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.orderTitle),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(CommerceRoutes.orders),
        ),
      ),
      bottomNavigationBar: BottomActions(
        children: <Widget>[
          if (rejected) ...<Widget>[
            AppButton(
              key: const Key('order-edit'),
              label: l10n.orderEditAndResend,
              icon: Icons.edit_outlined,
              onPressed: () => _edit(context, ref, v),
            ),
          ] else ...<Widget>[
            AppButton(
              key: const Key('order-share'),
              label: l10n.orderShareInvoice,
              icon: Icons.share_outlined,
              variant: AppButtonVariant.secondary,
              onPressed: shareReason == null
                  ? () => _share(context, ref, o)
                  : null,
            ),
            if (!paid && o.status != OrderStatuses.cancelled)
              AppButton(
                key: const Key('order-collect'),
                label: l10n.orderCollectPayment,
                icon: Icons.currency_rupee,
                onPressed: () =>
                    context.push(CommerceRoutes.cash(orderId: o.id)),
              )
            else
              AppButton(
                key: const Key('order-done'),
                label: l10n.paymentDone,
                icon: Icons.check,
                onPressed: () => o.farmerId == null
                    ? context.go(CommerceRoutes.orders)
                    : context.go('/farmers/${o.farmerId}'),
              ),
          ],
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: ListView(
                key: const Key('order-body'),
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  Row(
                    key: Key(
                      rejected
                          ? 'order-rejected'
                          : v.pendingSync
                          ? 'order-queued'
                          : 'order-placed',
                    ),
                    children: <Widget>[
                      Icon(icon, color: color, size: Tokens.space8),
                      const SizedBox(width: Tokens.space2),
                      Expanded(
                        child: Text(
                          title,
                          style: app.text.title.copyWith(color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Tokens.space1),
                  Text(
                    <String>[
                      farmerNameOf(ref, o.farmerId),
                      if (o.placedAt != null) formatDateTimeIst(o.placedAt!),
                      if (o.fulfilment == Fulfilment.delivery.name)
                        l10n.fulfilmentDelivery
                      else
                        l10n.fulfilmentPickup,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: app.text.body.copyWith(color: p.textSecondary),
                  ),
                  if (v.pendingSync) ...<Widget>[
                    const SizedBox(height: Tokens.space2),
                    Text(
                      l10n.orderQueuedHelp,
                      style: app.text.body.copyWith(color: p.statusInfo),
                    ),
                  ],
                  if (rejected) ...<Widget>[
                    const SizedBox(height: Tokens.space3),
                    _Rejection(view: v),
                  ],
                  if (!rejected) ...<Widget>[
                    const SizedBox(height: Tokens.space4),
                    Text(l10n.orderStatusTitle, style: app.text.heading),
                    const SizedBox(height: Tokens.space2),
                    _Timeline(view: v),
                  ],
                  const SizedBox(height: Tokens.space4),
                  Text(l10n.orderSummary, style: app.text.heading),
                  const SizedBox(height: Tokens.space2),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Tokens.space3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final l in v.lines)
                            Padding(
                              key: Key('order-line-${l.skuId}'),
                              padding: const EdgeInsets.symmetric(
                                vertical: Tokens.space1,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      <String>[
                                        '${l.productName} · ${l.packLabel}',
                                        '${qtyText(l.qty)} × '
                                            '${formatInr(l.unitPricePaise ?? l.estimatedUnitPricePaise)}',
                                      ].join('\n'),
                                      style: app.text.body,
                                    ),
                                  ),
                                  Text(
                                    formatInr(
                                      l.lineTotalPaise ??
                                          (l.estimatedUnitPricePaise * l.qty)
                                              .round(),
                                    ),
                                    style: app.text.body,
                                  ),
                                ],
                              ),
                            ),
                          const Divider(),
                          if (v.serverPriced) ...<Widget>[
                            MoneyRow(
                              label: l10n.orderSubtotal,
                              paise: o.subtotalPaise ?? 0,
                            ),
                            MoneyRow(
                              label: l10n.orderTax,
                              paise: o.taxPaise ?? 0,
                            ),
                          ],
                          MoneyRow(
                            key: const Key('order-total'),
                            label: v.serverPriced
                                ? l10n.orderTotal
                                : l10n.orderTotalEstimate,
                            paise: v.displayTotalPaise,
                            strong: true,
                          ),
                          if (o.invoiceNo != null)
                            Text(
                              l10n.orderInvoiceNo(o.invoiceNo!),
                              style: app.text.caption.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Tokens.space4),
                  Text(l10n.orderPayments, style: app.text.heading),
                  const SizedBox(height: Tokens.space2),
                  if (payments.isEmpty)
                    Text(
                      l10n.orderNoPayments,
                      style: app.text.body.copyWith(color: p.textSecondary),
                    ),
                  for (final pay in payments)
                    ListTile(
                      key: Key('order-payment-${pay.payment.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(switch (pay.payment.mode) {
                        PaymentModes.upiQr => Icons.qr_code_2,
                        PaymentModes.paymentLink => Icons.link,
                        PaymentModes.credit => Icons.menu_book_outlined,
                        _ => Icons.payments_outlined,
                      }),
                      title: Text(modeLabel(l10n, pay.payment.mode)),
                      subtitle: Text(collectionStateLabel(l10n, pay.state)),
                      trailing: Text(
                        formatInr(pay.payment.amountPaise),
                        style: app.text.heading,
                      ),
                      onTap: switch (pay.payment.mode) {
                        PaymentModes.upiQr => () => context.push(
                          CommerceRoutes.upi(pay.payment.id),
                        ),
                        PaymentModes.paymentLink => () => context.push(
                          CommerceRoutes.link(pay.payment.id),
                        ),
                        PaymentModes.credit => () => context.push(
                          CommerceRoutes.credit(pay.payment.id),
                        ),
                        _ => null,
                      },
                    ),
                  if (!rejected && shareReason != null) ...<Widget>[
                    const SizedBox(height: Tokens.space2),
                    Text(
                      shareReason,
                      key: const Key('order-share-reason'),
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.view});

  final OrderView view;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final status = view.order.status;
    if (status == OrderStatuses.cancelled) {
      return StatusPill(text: l10n.orderStatusCancelled, color: p.statusDanger);
    }
    final current = view.pendingSync ? -1 : OrderStatuses.stepOf(status);
    final times = <String, DateTime?>{
      for (final e in view.events) e.toStatus: e.at,
    };
    final steps = <String>[
      ...OrderStatuses.timeline.take(OrderStatuses.timeline.length - 1),
      if (status == OrderStatuses.delivered ||
          (view.order.fulfilment == Fulfilment.delivery.name &&
              status != OrderStatuses.handedOver))
        OrderStatuses.delivered
      else
        OrderStatuses.handedOver,
    ];
    return Column(
      key: const Key('order-timeline'),
      children: <Widget>[
        for (final (i, s) in steps.indexed)
          Row(
            key: Key('order-step-$s'),
            children: <Widget>[
              Icon(
                i <= current
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: i <= current ? p.statusSuccess : p.textMuted,
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Tokens.space1),
                  child: Text(
                    orderStatusLabel(l10n, s),
                    style: (i == current ? app.text.heading : app.text.body)
                        .copyWith(color: i <= current ? p.text : p.textMuted),
                  ),
                ),
              ),
              if (times[s] != null)
                Text(
                  formatTimeIst(times[s]!),
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
            ],
          ),
      ],
    );
  }
}

class _Rejection extends StatelessWidget {
  const _Rejection({required this.view});

  final OrderView view;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final error = view.rejection!;
    final names = <String, String>{
      for (final l in view.lines) l.skuId: l.productName,
    };
    final text = switch (error.code) {
      OrderErrorCodes.insufficientStock => <String>[
        l10n.orderInsufficientStock,
        for (final s in view.shortfalls)
          l10n.orderShortLine(
            names[s.skuId] ?? s.skuId,
            qtyText(s.available),
            qtyText(s.requested),
          ),
      ].join('\n'),
      OrderErrorCodes.skuNotRecommendable => l10n.orderSkuNotRecommendable,
      _ =>
        '${l10n.profileRejectedTitle}: ${error.detail.isEmpty ? error.code : error.detail}',
    };
    return Container(
      key: Key('order-rejection-${error.code}'),
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: app.tint(p.statusDangerContainer),
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.all(color: p.statusDanger, width: app.borderWidth),
      ),
      child: Text(text, style: app.text.body.copyWith(color: p.statusDanger)),
    );
  }
}
