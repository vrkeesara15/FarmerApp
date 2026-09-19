import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'shop_state.dart';

/// Products at the farmer's store by category (entry to F30). No search
/// box (NF-010): category chips and product cards only; the cart bar leads
/// to F31. Works from the cached catalogue offline.
class ShopScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  CatalogCategory? _category;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final storeId = ref.watch(kisanStoreIdProvider);
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.catalogTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            SizedBox(
              height: 64,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.spaceScreenPadding,
                  vertical: Tokens.space2,
                ),
                child: Row(
                  children: <Widget>[
                    for (final c in <CatalogCategory?>[
                      null,
                      ...CatalogCategory.values,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: Tokens.space2),
                        child: ChoiceChip(
                          key: Key('shop-category-${c?.wire ?? 'all'}'),
                          avatar: Icon(
                            c == null ? Icons.apps : categoryIcon(c),
                            size: Tokens.space4 + 2,
                          ),
                          label: Text(
                            c == null
                                ? l10n.catalogCategoryAll
                                : categoryLabel(l10n, c),
                          ),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: storeId.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const ErrorState(),
                data: (store) {
                  if (store == null) {
                    return EmptyState(
                      icon: Icons.storefront_outlined,
                      title: l10n.catalogNeverLoaded,
                      help: l10n.catalogNeverLoadedHelp,
                    );
                  }
                  final items = ref.watch(
                    catalogSearchProvider(
                      CatalogQuery(category: _category, storeId: store),
                    ),
                  );
                  final list = items.value ?? const <CatalogItem>[];
                  if (items.hasValue && list.isEmpty) {
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: l10n.catalogEmpty,
                      help: l10n.kisanShopEmptyHelp,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Tokens.space2),
                    itemBuilder: (context, i) {
                      final item = list[i];
                      return ProductCard(
                        key: Key('shop-product-${item.skuId}'),
                        name: item.nameIn(lang),
                        pack: item.packLabel,
                        pricePaise: item.pricePaise,
                        ownBrand: item.ownBrand,
                        stockCount: item.stock?.wholeUnits,
                        added: cart.qtyOf(item.skuId) > 0,
                        onTap: () =>
                            context.push(AppRoutes.product(item.skuId)),
                        onAdd: () =>
                            context.push(AppRoutes.product(item.skuId)),
                      );
                    },
                  );
                },
              ),
            ),
            if (cart.lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(Tokens.space2),
                child: CartBar(
                  key: const Key('shop-cart-bar'),
                  itemCount: cart.totals.itemCount,
                  totalPaise: cart.totals.totalPaise,
                  estimate: true,
                  actionLabel: l10n.kisanViewCart,
                  onCheckout: () => context.push(AppRoutes.cart),
                ),
              ),
            if (cart.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Tokens.space2),
                child: Text(
                  l10n.kisanShopHelp,
                  style: app.text.caption.copyWith(
                    color: app.palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reads a cached catalogue item for [skuId] at the farmer's store.
final kisanItemProvider = FutureProvider.family<CatalogItem?, String>((
  ref,
  skuId,
) async {
  final storeId = await ref.watch(kisanStoreIdProvider.future);
  return ref.watch(catalogCacheProvider).item(skuId, storeId: storeId);
});

/// Shared quantity stepper (48 dp buttons).
class QtyStepper extends StatelessWidget {
  /// Creates the stepper.
  const QtyStepper({
    required this.qty,
    required this.onChanged,
    this.keyPrefix = 'qty',
    super.key,
  });

  /// Quantity.
  final int qty;

  /// New quantity.
  final ValueChanged<int> onChanged;

  /// Button key prefix (tests).
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton.outlined(
          key: Key('$keyPrefix-dec'),
          tooltip: l10n.kisanLess,
          constraints: const BoxConstraints.tightFor(
            width: Tokens.sizeTouchTargetMin,
            height: Tokens.sizeTouchTargetMin,
          ),
          onPressed: qty > 0 ? () => onChanged(qty - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: Tokens.space12,
          child: Text(
            '$qty',
            key: Key('$keyPrefix-value'),
            textAlign: TextAlign.center,
            style: app.text.title,
          ),
        ),
        IconButton.outlined(
          key: Key('$keyPrefix-inc'),
          tooltip: l10n.kisanMore,
          constraints: const BoxConstraints.tightFor(
            width: Tokens.sizeTouchTargetMin,
            height: Tokens.sizeTouchTargetMin,
          ),
          onPressed: () => onChanged(qty + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
