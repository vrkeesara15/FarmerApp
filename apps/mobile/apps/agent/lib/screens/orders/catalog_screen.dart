import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'commerce_copy.dart';

/// A50 Product search and catalogue for a farmer (FA-020): search by name /
/// brand / active ingredient, category chips, ProductCards with the
/// own-brand badge, estimated price and "stock at the store, as of the time",
/// stale-data indicator, CartBar. Reads only the offline cache; refreshes
/// it (and the nearest store's availability) when online.
class CatalogScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CatalogScreen({required this.farmerId, super.key});

  /// Farmer the order is for.
  final String farmerId;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final TextEditingController _search = TextEditingController();
  CatalogCategory? _category;
  bool _refreshing = false;
  bool _refreshFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final cache = ref.read(catalogCacheProvider);
    final cart = ref.read(cartProvider.notifier);
    final known = await cache.storeIdForFarmer(widget.farmerId);
    if (!mounted) return;
    cart.start(widget.farmerId, storeId: known);
    final online = await ref.read(connectivityMonitorProvider).isOnline();
    if (!online) return;
    final storeId = ref.read(cartProvider).storeId;
    final stale =
        storeId == null ||
        await cache.isEmpty() ||
        CatalogCache.isStale(
          (await cache.store(storeId))?.catalogRefreshedAt,
          ref.read(clockProvider)(),
        );
    if (stale) await _refresh();
  }

  Future<void> _refresh() async {
    final cache = ref.read(catalogCacheProvider);
    setState(() {
      _refreshing = true;
      _refreshFailed = false;
    });
    var ok = true;
    try {
      final nearest = await cache.nearestStore(widget.farmerId);
      if (nearest != null) {
        ref.read(cartProvider.notifier).setStore(nearest.store.id);
      }
      final storeId = ref.read(cartProvider).storeId;
      if (storeId == null) {
        ok = nearest != null;
      } else {
        await cache.refresh(storeId: storeId);
        final items = await cache.search(CatalogQuery(storeId: storeId));
        await cache.nearestStore(
          widget.farmerId,
          skuIds: <String>[for (final i in items.take(50)) i.skuId],
        );
      }
    } on CatalogUnavailableException {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _refreshFailed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final storeId = cart.storeId;
    final store = storeId == null
        ? null
        : ref.watch(catalogStoreProvider(storeId)).value;
    final query = CatalogQuery(
      text: _search.text,
      category: _category,
      storeId: storeId,
    );
    final results = ref.watch(catalogSearchProvider(query));
    final offline = ref.watch(offlineProvider);
    final now = ref.watch(clockProvider)();
    final refreshedAt = store?.catalogRefreshedAt;
    final stale = CatalogCache.isStale(refreshedAt, now);
    final name = farmerNameOf(ref, widget.farmerId);
    final lang = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.catalogTitle),
            if (name.isNotEmpty)
              Text(
                l10n.catalogForFarmer(name),
                style: app.text.caption.copyWith(color: p.textSecondary),
              ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('catalog-refresh'),
            tooltip: l10n.catalogRefresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: Tokens.space4,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: offline || _refreshing ? null : _refresh,
          ),
        ],
      ),
      bottomNavigationBar: cart.lines.isEmpty
          ? null
          : CartBar(
              key: const Key('cart-bar'),
              itemCount: cart.totals.itemCount,
              totalPaise: cart.totals.totalPaise,
              estimate: true,
              actionLabel: l10n.cartViewCart,
              onCheckout: () => context.push(CommerceRoutes.cart),
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.spaceScreenPadding,
                Tokens.space3,
                Tokens.spaceScreenPadding,
                0,
              ),
              child: TextField(
                key: const Key('catalog-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.catalogSearchHint,
                ),
              ),
            ),
            SingleChildScrollView(
              key: const Key('catalog-categories'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.spaceScreenPadding,
                vertical: Tokens.space2,
              ),
              child: Row(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: Tokens.space2),
                    child: ChoiceChip(
                      key: const Key('catalog-category-all'),
                      label: Text(l10n.catalogCategoryAll),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                  ),
                  for (final c in CatalogCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Tokens.space2),
                      child: ChoiceChip(
                        key: Key('catalog-category-${c.wire}'),
                        label: Text(categoryLabel(l10n, c)),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
            if (refreshedAt != null)
              _FreshnessLine(
                key: const Key('catalog-freshness'),
                text: stale || offline
                    ? l10n.catalogStale(formatDateTimeIst(refreshedAt))
                    : l10n.catalogAsOf(formatDateTimeIst(refreshedAt)),
                warn: stale || offline,
              ),
            if (_refreshFailed)
              _FreshnessLine(
                key: const Key('catalog-refresh-failed'),
                text: l10n.catalogRefreshFailed,
                warn: true,
              ),
            if (storeId == null)
              _FreshnessLine(
                key: const Key('catalog-store-unknown'),
                text: l10n.catalogStoreUnknown,
                warn: true,
              ),
            Expanded(
              child: results.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Tokens.spaceScreenPadding),
                  child: Skeletons.list(),
                ),
                error: (e, _) => ErrorState(
                  onRetry: () => ref.invalidate(catalogSearchProvider(query)),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    final never =
                        refreshedAt == null &&
                        query.text.isEmpty &&
                        query.category == null;
                    return Center(
                      child: EmptyState(
                        key: Key(never ? 'catalog-never' : 'catalog-empty'),
                        icon: never
                            ? Icons.cloud_download_outlined
                            : Icons.search_off,
                        title: never
                            ? l10n.catalogNeverLoaded
                            : l10n.catalogEmpty,
                        help: never
                            ? l10n.catalogNeverLoadedHelp
                            : l10n.catalogEmptyHelp,
                      ),
                    );
                  }
                  return ListView.separated(
                    key: const Key('catalog-list'),
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Tokens.space2),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final qty = cart.qtyOf(item.skuId);
                      return ProductCard(
                        key: Key('product-${item.skuId}'),
                        name: item.nameIn(lang),
                        pack: item.packLabel,
                        pricePaise: item.pricePaise,
                        priceIsEstimate: true,
                        ownBrand: item.ownBrand,
                        stockCount: item.stock?.wholeUnits,
                        storeName: store?.name,
                        stockAsOf: item.stock?.asOf,
                        added: qty > 0,
                        quantity: qty > 0 ? qty : null,
                        onAdd: () => ref.read(cartProvider.notifier).add(item),
                      );
                    },
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

class _FreshnessLine extends StatelessWidget {
  const _FreshnessLine({required this.text, required this.warn, super.key});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final color = warn ? p.statusWarning : p.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.spaceScreenPadding,
        vertical: Tokens.space1,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            warn ? Icons.history_toggle_off : Icons.schedule,
            size: Tokens.space4,
            color: color,
          ),
          const SizedBox(width: Tokens.space1),
          Expanded(
            child: Text(text, style: app.text.caption.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
