import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Orders, payments and khata routes (SPEC 13.2 A50–A59).
abstract final class CommerceRoutes {
  /// Orders tab of the bottom nav.
  static const String orders = '/orders';

  /// A59 Collections list.
  static const String collections = '/collections';

  /// Farmer picker before A50 / A52 (Home and Orders entry points).
  static String pickFarmer(PickPurpose purpose) =>
      '/orders/pick?for=${purpose.name}';

  /// A50 Catalogue for a farmer.
  static String catalogue(String farmerId) => Uri(
    path: '/orders/new',
    queryParameters: {'farmerId': farmerId},
  ).toString();

  /// A51 Cart.
  static const String cart = '/orders/cart';

  /// A52 Payment method for the cart's order.
  static const String checkout = '/orders/checkout';

  /// A57 Order success / detail.
  static String order(String id) => '/orders/$id';

  /// A53 UPI QR.
  static String upi(String paymentId) => '/payments/$paymentId/upi';

  /// A54 Payment link sent.
  static String link(String paymentId) => '/payments/$paymentId/link';

  /// A56 Credit sale.
  static String credit(String paymentId) => '/payments/$paymentId/credit';

  /// A55 Cash receipt for an order, or for dues ([amountPaise] at [storeId]).
  static String cash({
    String? orderId,
    String? farmerId,
    String? storeId,
    int? amountPaise,
  }) => Uri(
    path: '/payments/cash',
    queryParameters: <String, String>{
      'orderId': ?orderId,
      'farmerId': ?farmerId,
      'storeId': ?storeId,
      'amount': ?amountPaise?.toString(),
    },
  ).toString();

  /// A58 Khata of a farmer.
  static String khata(String farmerId) => '/farmers/$farmerId/khata';

  /// A52 in dues mode (Collect from A22 / A58 / Home).
  static String collect(String farmerId) => '/farmers/$farmerId/collect';
}

/// Why the farmer picker opened.
enum PickPurpose {
  /// Then A50.
  order,

  /// Then A52 dues mode.
  collect,

  /// Then the crop plot choice for scouting (FA-019).
  scout,
}

/// Localised category label.
String categoryLabel(CoreLocalizations l10n, CatalogCategory c) => switch (c) {
  CatalogCategory.seed => l10n.catalogCategorySeed,
  CatalogCategory.fertiliser => l10n.catalogCategoryFertiliser,
  CatalogCategory.pesticide => l10n.catalogCategoryPesticide,
  CatalogCategory.fungicide => l10n.catalogCategoryFungicide,
  CatalogCategory.herbicide => l10n.catalogCategoryHerbicide,
  CatalogCategory.growth => l10n.catalogCategoryGrowth,
  CatalogCategory.tool => l10n.catalogCategoryTool,
  CatalogCategory.other => l10n.catalogCategoryOther,
};

/// Localised payment mode label.
String modeLabel(CoreLocalizations l10n, String mode) => switch (mode) {
  PaymentModes.upiQr => l10n.paymentUpiQr,
  PaymentModes.paymentLink => l10n.paymentLink,
  PaymentModes.credit => l10n.paymentCredit,
  PaymentModes.cardTerminal => l10n.paymentCard,
  _ => l10n.paymentCash,
};

/// Localised order status label.
String orderStatusLabel(CoreLocalizations l10n, String status) =>
    switch (status) {
      OrderStatuses.reserved => l10n.orderStatusReserved,
      OrderStatuses.packed => l10n.orderStatusPacked,
      OrderStatuses.ready => l10n.orderStatusReady,
      OrderStatuses.handedOver => l10n.orderStatusHandedOver,
      OrderStatuses.delivered => l10n.orderStatusDelivered,
      OrderStatuses.cancelled => l10n.orderStatusCancelled,
      _ => l10n.orderStatusPlaced,
    };

/// Localised A59 state label.
String collectionStateLabel(CoreLocalizations l10n, CollectionState s) =>
    switch (s) {
      CollectionState.waitingToSync => l10n.collectionStateWaitingToSync,
      CollectionState.pendingReconciliation =>
        l10n.collectionStatePendingReconciliation,
      CollectionState.waiting => l10n.collectionStateWaiting,
      CollectionState.paid => l10n.collectionStatePaid,
      CollectionState.onKhata => l10n.collectionStateOnKhata,
      CollectionState.approvalNeeded => l10n.collectionStateApprovalNeeded,
      CollectionState.failed => l10n.collectionStateFailed,
    };

/// Status colour of an A59 state.
Color collectionStateColor(TokenPalette p, CollectionState s) => switch (s) {
  CollectionState.paid || CollectionState.onKhata => p.statusSuccess,
  CollectionState.failed => p.statusDanger,
  CollectionState.approvalNeeded ||
  CollectionState.pendingReconciliation => p.statusWarning,
  CollectionState.waitingToSync || CollectionState.waiting => p.statusInfo,
};

/// Farmer display name (empty while loading).
String farmerNameOf(WidgetRef ref, String? farmerId) {
  if (farmerId == null) return '';
  return ref.watch(farmerDetailProvider(farmerId)).value?.farmer.name ?? '';
}

/// Formats a decimal quantity without trailing zeros (`2`, `1.5`).
String qtyText(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// Label + amount row (totals).
class MoneyRow extends StatelessWidget {
  /// Creates the row.
  const MoneyRow({
    required this.label,
    required this.paise,
    this.strong = false,
    super.key,
  });

  /// Label.
  final String label;

  /// Amount.
  final int paise;

  /// Heading style.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final style = strong ? app.text.heading : app.text.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space1),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(formatInr(paise), style: style),
        ],
      ),
    );
  }
}

/// Small coloured status pill.
class StatusPill extends StatelessWidget {
  /// Creates the pill.
  const StatusPill({required this.text, required this.color, super.key});

  /// Text.
  final String text;

  /// Colour.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: color, width: app.borderWidth),
      ),
      child: Text(
        text,
        style: app.text.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Bottom area with one full-width primary action (and optional
/// secondary action above it).
class BottomActions extends StatelessWidget {
  /// Creates the area.
  const BottomActions({required this.children, super.key});

  /// Buttons, top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(Tokens.space4),
        decoration: BoxDecoration(
          color: app.palette.surface,
          border: Border(top: app.borderSide),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (i, c) in children.indexed) ...<Widget>[
              if (i > 0) const SizedBox(height: Tokens.space2),
              c,
            ],
          ],
        ),
      ),
    );
  }
}

/// Runs a sync now when the device is online (the caller then reads the
/// op result); returns whether it ran.
Future<bool> syncIfOnline(WidgetRef ref) async {
  final online = await ref.read(connectivityMonitorProvider).isOnline();
  if (!online) return false;
  await ref.read(syncEngineProvider).syncNow();
  return true;
}

/// Before returning to A57 from a payment screen: the order page below was
/// paused while covered (Riverpod ticker mode), so its streams are
/// refreshed to show the new payment at once.
void refreshOrder(WidgetRef ref, String orderId) {
  ref
    ..invalidate(orderViewProvider(orderId))
    ..invalidate(orderPaymentsProvider(orderId));
}
