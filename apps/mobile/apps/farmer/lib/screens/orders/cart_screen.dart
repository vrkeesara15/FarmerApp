import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';
import 'shop_screen.dart';

/// F31 Cart and pickup or delivery choice: quantities with big +/−, the
/// estimated total, and two tiles (Pickup at store / Home delivery).
class CartScreen extends ConsumerWidget {
  /// Creates the screen.
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanCartTitle)),
      body: SafeArea(
        child: cart.lines.isEmpty
            ? EmptyState(
                icon: Icons.shopping_cart_outlined,
                title: l10n.kisanCartEmpty,
                help: l10n.kisanShopHelp,
                actionLabel: l10n.kisanBuyProducts,
                onAction: () => context.pushReplacement(AppRoutes.shop),
              )
            : Column(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                      children: <Widget>[
                        for (final line in cart.lines)
                          Card(
                            key: Key('cart-line-${line.item.skuId}'),
                            child: Padding(
                              padding: const EdgeInsets.all(Tokens.space3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    line.item.nameIn(lang),
                                    style: app.text.heading,
                                  ),
                                  Text(
                                    '${line.item.packLabel} · '
                                    '${formatInr(line.item.pricePaise)}',
                                    style: app.text.body,
                                  ),
                                  const SizedBox(height: Tokens.space2),
                                  QtyStepper(
                                    qty: line.qty,
                                    keyPrefix: 'cart-qty-${line.item.skuId}',
                                    onChanged: (v) =>
                                        notifier.setQty(line.item, v),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: Tokens.space3),
                        SpokenText(
                          promptId: 'f31_pickup',
                          text: l10n.kisanPickupQuestion,
                          style: app.text.heading,
                        ),
                        ChoiceGrid(
                          columns: 2,
                          children: <Widget>[
                            ChoiceTile(
                              key: const Key('cart-pickup'),
                              icon: Icons.storefront_outlined,
                              label: l10n.kisanPickup,
                              selected: cart.fulfilment == Fulfilment.pickup,
                              onTap: () =>
                                  notifier.setFulfilment(Fulfilment.pickup),
                            ),
                            ChoiceTile(
                              key: const Key('cart-delivery'),
                              icon: Icons.local_shipping_outlined,
                              label: l10n.kisanDelivery,
                              selected: cart.fulfilment == Fulfilment.delivery,
                              onTap: () =>
                                  notifier.setFulfilment(Fulfilment.delivery),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Tokens.space2),
                    child: CartBar(
                      key: const Key('cart-bar'),
                      itemCount: cart.totals.itemCount,
                      totalPaise: cart.totals.totalPaise,
                      estimate: true,
                      actionLabel: l10n.kisanGoToPay,
                      onCheckout: () => context.push(AppRoutes.pay),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
