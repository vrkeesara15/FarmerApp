import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'commerce_copy.dart';

/// A51 Cart (FA-020): quantities, estimated prices, pickup / delivery,
/// estimated totals and CartBar to A52. After an `insufficient_stock`
/// rejection each short line shows what the store has and "Use N".
class CartScreen extends ConsumerWidget {
  /// Creates the screen.
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final totals = cart.totals;
    final lang = Localizations.localeOf(context).languageCode;
    final editing = cart.editingOrderId != null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.cartTitle),
            if (cart.farmerId != null)
              Text(
                l10n.catalogForFarmer(farmerNameOf(ref, cart.farmerId)),
                style: app.text.caption.copyWith(color: p.textSecondary),
              ),
          ],
        ),
      ),
      bottomNavigationBar: cart.lines.isEmpty
          ? null
          : CartBar(
              key: const Key('cart-bar'),
              itemCount: totals.itemCount,
              totalPaise: totals.totalPaise,
              estimate: true,
              actionLabel: l10n.cartChoosePayment,
              onCheckout: cart.hasShortLines
                  ? null
                  : () => context.push(CommerceRoutes.checkout),
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: cart.lines.isEmpty
                  ? Center(
                      child: EmptyState(
                        key: const Key('cart-empty'),
                        icon: Icons.shopping_cart_outlined,
                        title: l10n.cartEmpty,
                        help: l10n.cartEmptyHelp,
                        actionLabel: cart.farmerId == null
                            ? null
                            : l10n.cartAddMore,
                        onAction: cart.farmerId == null
                            ? null
                            : () => context.pushReplacement(
                                CommerceRoutes.catalogue(cart.farmerId!),
                              ),
                      ),
                    )
                  : ListView(
                      key: const Key('cart-list'),
                      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                      children: <Widget>[
                        if (editing && cart.shortfalls.isNotEmpty) ...<Widget>[
                          _Notice(
                            key: const Key('cart-short-notice'),
                            text: l10n.cartShortTitle,
                            color: p.statusDanger,
                            container: p.statusDangerContainer,
                          ),
                          const SizedBox(height: Tokens.space3),
                        ],
                        for (final line in cart.lines) ...<Widget>[
                          _LineCard(
                            key: Key('cart-line-${line.item.skuId}'),
                            line: line,
                            name: line.item.nameIn(lang),
                            shortfall: cart.shortfallOf(line.item.skuId),
                            onQty: (q) => notifier.setQty(line.item, q),
                          ),
                          const SizedBox(height: Tokens.space2),
                        ],
                        if (cart.farmerId != null && !editing)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: AppButton(
                              key: const Key('cart-add-more'),
                              label: l10n.cartAddMore,
                              icon: Icons.add,
                              variant: AppButtonVariant.tertiary,
                              size: AppButtonSize.medium,
                              expand: false,
                              onPressed: () => context.canPop()
                                  ? context.pop()
                                  : context.go(
                                      CommerceRoutes.catalogue(cart.farmerId!),
                                    ),
                            ),
                          ),
                        const SizedBox(height: Tokens.space3),
                        Text(l10n.cartFulfilment, style: app.text.heading),
                        const SizedBox(height: Tokens.space2),
                        SegmentedButton<Fulfilment>(
                          key: const Key('cart-fulfilment'),
                          segments: <ButtonSegment<Fulfilment>>[
                            ButtonSegment<Fulfilment>(
                              value: Fulfilment.pickup,
                              icon: const Icon(Icons.storefront_outlined),
                              label: Text(l10n.fulfilmentPickup),
                            ),
                            ButtonSegment<Fulfilment>(
                              value: Fulfilment.delivery,
                              icon: const Icon(Icons.local_shipping_outlined),
                              label: Text(l10n.fulfilmentDelivery),
                            ),
                          ],
                          selected: <Fulfilment>{cart.fulfilment},
                          onSelectionChanged: editing
                              ? null
                              : (s) => notifier.setFulfilment(s.first),
                        ),
                        const SizedBox(height: Tokens.space4),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(Tokens.space3),
                            child: Column(
                              children: <Widget>[
                                MoneyRow(
                                  label: l10n.cartSubtotal,
                                  paise: totals.subtotalPaise,
                                ),
                                MoneyRow(
                                  label: l10n.cartTax,
                                  paise: totals.taxPaise,
                                ),
                                const Divider(),
                                MoneyRow(
                                  key: const Key('cart-total'),
                                  label: l10n.cartEstimatedTotal,
                                  paise: totals.totalPaise,
                                  strong: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: Tokens.space2),
                        Text(
                          l10n.cartEstimateNote,
                          style: app.text.caption.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.name,
    required this.shortfall,
    required this.onQty,
    super.key,
  });

  final CartLine line;
  final String name;
  final StockShortfall? shortfall;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final short = shortfall != null && line.qty > shortfall!.available;
    final available = shortfall?.available.floor() ?? 0;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: short
            ? BorderSide(color: p.statusDanger, width: app.borderWidth + 1)
            : app.borderSide,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (line.item.ownBrand) ...<Widget>[
                        const OwnBrandBadge(),
                        const SizedBox(height: Tokens.space1),
                      ],
                      Text(name, style: app.text.heading),
                      Text(
                        '${l10n.productPack}: ${line.item.packLabel} · '
                        '${formatInr(line.item.pricePaise)}',
                        style: app.text.caption.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatInr(line.estimatedLinePaise),
                  style: app.text.heading,
                ),
              ],
            ),
            const SizedBox(height: Tokens.space2),
            Row(
              children: <Widget>[
                IconButton.outlined(
                  key: Key('cart-dec-${line.item.skuId}'),
                  tooltip: l10n.cartDecrease,
                  icon: Icon(
                    line.qty == 1 ? Icons.delete_outline : Icons.remove,
                  ),
                  onPressed: () => onQty(line.qty - 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.space3,
                  ),
                  child: Text(
                    '${line.qty}',
                    key: Key('cart-qty-${line.item.skuId}'),
                    style: app.text.title,
                  ),
                ),
                IconButton.outlined(
                  key: Key('cart-inc-${line.item.skuId}'),
                  tooltip: l10n.cartIncrease,
                  icon: const Icon(Icons.add),
                  onPressed: () => onQty(line.qty + 1),
                ),
              ],
            ),
            if (short) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              Text(
                l10n.cartShortLine(
                  qtyText(shortfall!.available),
                  qtyText(shortfall!.requested),
                ),
                key: Key('cart-short-${line.item.skuId}'),
                style: app.text.body.copyWith(color: p.statusDanger),
              ),
              if (available > 0)
                AppButton(
                  key: Key('cart-use-available-${line.item.skuId}'),
                  label: l10n.cartUseAvailable(qtyText(shortfall!.available)),
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  expand: false,
                  onPressed: () => onQty(available),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.color,
    required this.container,
    super.key,
  });

  final String text;
  final Color color;
  final Color container;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Container(
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: app.tint(container),
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.all(color: color, width: app.borderWidth),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_outlined, color: color),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Text(text, style: app.text.body.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
