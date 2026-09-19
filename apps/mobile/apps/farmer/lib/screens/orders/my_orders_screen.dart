import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';
import 'shop_state.dart';

/// F34 My orders (FM-010): newest first with status and total, a "Buy
/// products" action, and the khata shortcut. Cached for offline viewing.
class MyOrdersScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(kisanRepositoryProvider).refreshOrders());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final orders = ref.watch(kisanOrdersProvider);
    return KisanTabScaffold(
      tab: KisanTab.orders,
      title: l10n.kisanMyOrders,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.spaceScreenPadding,
              Tokens.space3,
              Tokens.spaceScreenPadding,
              0,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    key: const Key('orders-buy'),
                    label: l10n.kisanBuyProducts,
                    icon: Icons.add_shopping_cart,
                    size: AppButtonSize.medium,
                    onPressed: () => context.push(AppRoutes.shop),
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: AppButton(
                    key: const Key('orders-khata'),
                    label: l10n.khataTitle,
                    icon: Icons.menu_book_outlined,
                    size: AppButtonSize.medium,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.push(AppRoutes.khata),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: orders.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const ErrorState(),
              data: (cached) {
                final list = cached?.value ?? const <KisanOrder>[];
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: l10n.ordersEmpty,
                    help: cached == null
                        ? l10n.kisanNeedsInternet
                        : l10n.kisanOrdersEmptyHelp,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(kisanRepositoryProvider).refreshOrders(),
                  child: ListView(
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    children: <Widget>[
                      for (final o in list)
                        Card(
                          key: Key('order-row-${o.id}'),
                          child: ListTile(
                            minTileHeight: 64,
                            leading: Icon(
                              o.step == 3
                                  ? Icons.check_circle_outline
                                  : Icons.local_shipping_outlined,
                              color: o.step < 0 ? p.statusDanger : p.primary,
                            ),
                            title: Text(
                              orderStatusLabel(l10n, o.status),
                              style: app.text.heading,
                            ),
                            subtitle: o.placedAt == null
                                ? null
                                : Text(formatDateIst(o.placedAt!)),
                            trailing: Text(
                              formatInr(o.totalPaise),
                              style: app.text.label,
                            ),
                            onTap: () => context.push(AppRoutes.order(o.id)),
                          ),
                        ),
                      AsOfLabel(cached!.asOf),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
