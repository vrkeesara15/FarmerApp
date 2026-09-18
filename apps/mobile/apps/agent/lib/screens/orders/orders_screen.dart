import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'commerce_copy.dart';

/// One order row (Orders tab, A22 Orders tab).
class OrderSummaryTile extends ConsumerWidget {
  /// Creates the row.
  const OrderSummaryTile({
    required this.view,
    this.showFarmer = true,
    super.key,
  });

  /// The order.
  final OrderView view;

  /// Show the farmer name (off on the farmer's own profile).
  final bool showFarmer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final o = view.order;
    final (String state, Color color) = view.rejection != null
        ? (l10n.orderRejected, p.statusDanger)
        : view.pendingSync
        ? (l10n.orderPendingSync, p.statusInfo)
        : (orderStatusLabel(l10n, o.status), p.statusSuccess);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: app.borderSide,
      ),
      child: InkWell(
        key: Key('order-row-${o.id}'),
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        onTap: () => context.push(CommerceRoutes.order(o.id)),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space3),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (showFarmer)
                      Text(
                        farmerNameOf(ref, o.farmerId),
                        style: app.text.heading,
                      ),
                    Text(
                      view.lines
                          .map((l) => '${l.productName} × ${qtyText(l.qty)}')
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: app.text.body.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: Tokens.space1),
                    Row(
                      children: <Widget>[
                        StatusPill(text: state, color: color),
                        if (o.placedAt != null) ...<Widget>[
                          const SizedBox(width: Tokens.space2),
                          Text(
                            formatDateTimeIst(o.placedAt!),
                            style: app.text.caption.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.space2),
              Text(formatInr(view.displayTotalPaise), style: app.text.heading),
            ],
          ),
        ),
      ),
    );
  }
}

/// Orders tab of the bottom nav: recent orders, "New order" (farmer
/// picker → A50) and the A59 collections list.
class OrdersScreen extends ConsumerWidget {
  /// Creates the screen.
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final orders = ref.watch(recentOrdersProvider).value ?? const <OrderView>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ordersTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('orders-collections'),
            tooltip: l10n.ordersCollections,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => context.push(CommerceRoutes.collections),
          ),
          SyncStatusPillLive(onTap: () => context.push('/settings/sync')),
          const SizedBox(width: Tokens.space3),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('orders-new'),
        icon: const Icon(Icons.add_shopping_cart),
        label: Text(l10n.ordersNew),
        onPressed: () =>
            context.push(CommerceRoutes.pickFarmer(PickPurpose.order)),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: orders.isEmpty
                  ? Center(
                      child: EmptyState(
                        key: const Key('orders-empty'),
                        icon: Icons.shopping_bag_outlined,
                        title: l10n.ordersEmpty,
                        help: l10n.ordersEmptyHelp,
                      ),
                    )
                  : ListView.separated(
                      key: const Key('orders-list'),
                      padding: const EdgeInsets.fromLTRB(
                        Tokens.spaceScreenPadding,
                        Tokens.spaceScreenPadding,
                        Tokens.spaceScreenPadding,
                        Tokens.space12 + Tokens.space8,
                      ),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Tokens.space2),
                      itemBuilder: (context, i) =>
                          OrderSummaryTile(view: orders[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks a farmer before A50 (new order) or A52 dues (collect).
class FarmerPickerScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const FarmerPickerScreen({required this.purpose, super.key});

  /// What happens next.
  final PickPurpose purpose;

  @override
  ConsumerState<FarmerPickerScreen> createState() => _FarmerPickerScreenState();
}

class _FarmerPickerScreenState extends ConsumerState<FarmerPickerScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final rows =
        ref.watch(farmerListProvider(FarmerListFilter(query: _query))).value ??
        const <FarmerSummary>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ordersPickFarmer)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              child: TextField(
                key: const Key('pick-search'),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.farmersSearchHint,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.spaceScreenPadding,
                ),
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: Tokens.space2),
                itemBuilder: (context, i) {
                  final f = rows[i];
                  return FarmerCard(
                    key: Key('pick-farmer-${f.id}'),
                    name: f.name,
                    village: f.villageName,
                    pendingSync: f.pendingSync,
                    onTap: () => context.pushReplacement(
                      widget.purpose == PickPurpose.order
                          ? CommerceRoutes.catalogue(f.id)
                          : CommerceRoutes.collect(f.id),
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
