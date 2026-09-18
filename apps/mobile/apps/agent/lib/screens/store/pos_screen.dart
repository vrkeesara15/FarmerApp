import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'store_routes.dart';
import 'store_shell.dart';

/// S02 POS: product grid with search and category chips, barcode scan
/// (camera) and manual code entry, farmer lookup by phone (walk-in allowed)
/// and the cart panel. Two panes at >= 700 dp; phones get a CartBar.
class PosScreen extends ConsumerWidget {
  /// Creates the screen.
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final role = ref.watch(storeRoleProvider);
    final pos = ref.watch(posProvider);
    final twoPane = isStoreTwoPane(context);
    final catalog = ref.watch(storeCatalogProvider);
    final grid = Column(
      key: const Key('pos-grid-pane'),
      children: <Widget>[
        const _SearchBar(),
        const _BuyerBar(),
        Expanded(
          child: StoreResultView<List<StoreItem>>(
            value: catalog,
            onRetry: () => ref.invalidate(storeCatalogProvider),
            builder: (items) => _ProductGrid(items: items),
          ),
        ),
      ],
    );
    return StoreShell(
      section: StoreSection.pos,
      title: l10n.storePosTitle,
      body: !role.canSell
          ? EmptyState(
              icon: Icons.lock_outline,
              title: l10n.storeNotAllowedTitle,
              help: l10n.storeReadOnlyBanner,
            )
          : twoPane
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: grid),
                VerticalDivider(width: 1, color: context.app.palette.border),
                const SizedBox(
                  width: 320,
                  child: CartPanel(
                    key: Key('pos-cart-pane'),
                    showCheckout: true,
                  ),
                ),
              ],
            )
          : Column(
              children: <Widget>[
                Expanded(child: grid),
                CartBar(
                  key: const Key('pos-cart-bar'),
                  itemCount: pos.itemCount,
                  totalPaise: pos.preview.totalPaise,
                  onCheckout: pos.lines.isEmpty
                      ? null
                      : () => context.push(StoreRoutes.checkout),
                ),
              ],
            ),
    );
  }
}

/// Handles a scan / typed code: adds the SKU or reports why not.
Future<void> addByCode(BuildContext context, WidgetRef ref, String code) async {
  final l10n = CoreLocalizations.of(context);
  final outcome = await ref.read(posProvider.notifier).scan(code);
  if (!context.mounted) return;
  final state = ref.read(posProvider);
  storeSnack(context, switch (outcome) {
    ScanOutcome.added => l10n.storeScanAdded(
      state.lines
          .lastWhere(
            (l) => l.item.barcode == code.trim(),
            orElse: () => state.lines.last,
          )
          .item
          .name,
    ),
    ScanOutcome.notFound => l10n.storeScanNotFound(code.trim()),
    ScanOutcome.offline => l10n.storeScanOffline,
  });
}

/// Manual barcode entry dialog.
Future<String?> askForCode(BuildContext context) {
  final l10n = CoreLocalizations.of(context);
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.storeEnterCode),
      content: TextField(
        key: const Key('pos-code-field'),
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(hintText: l10n.storeCodeHint),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('pos-code-add'),
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(l10n.storeCodeAdd),
        ),
      ],
    ),
  );
}

class _SearchBar extends ConsumerWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final pos = ref.watch(posProvider);
    final notifier = ref.read(posProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.spaceScreenPadding,
        Tokens.space3,
        Tokens.spaceScreenPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('pos-search'),
            onChanged: notifier.setQuery,
            decoration: InputDecoration(
              hintText: l10n.storeSearchProducts,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: Tokens.space2),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  key: const Key('pos-scan'),
                  label: l10n.storeScan,
                  icon: Icons.qr_code_scanner,
                  size: AppButtonSize.medium,
                  onPressed: () async {
                    final code = await ref
                        .read(barcodeScannerProvider)
                        .scan(context);
                    if (code != null && context.mounted) {
                      await addByCode(context, ref, code);
                    }
                  },
                ),
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: AppButton(
                  key: const Key('pos-enter-code'),
                  label: l10n.storeEnterCode,
                  icon: Icons.keyboard_outlined,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  onPressed: () async {
                    final code = await askForCode(context);
                    if (code != null &&
                        code.trim().isNotEmpty &&
                        context.mounted) {
                      await addByCode(context, ref, code);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.space2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                ChoiceChip(
                  key: const Key('pos-cat-all'),
                  label: Text(l10n.storeCategoryAll),
                  selected: pos.category == null,
                  onSelected: (_) => notifier.setCategory(null),
                ),
                for (final c in storeCategories) ...<Widget>[
                  const SizedBox(width: Tokens.space2),
                  ChoiceChip(
                    key: Key('pos-cat-$c'),
                    label: Text(categoryLabel(l10n, c)),
                    selected: pos.category == c,
                    onSelected: (_) => notifier.setCategory(c),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyerBar extends ConsumerStatefulWidget {
  const _BuyerBar();

  @override
  ConsumerState<_BuyerBar> createState() => _BuyerBarState();
}

class _BuyerBarState extends ConsumerState<_BuyerBar> {
  final TextEditingController _phone = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final buyer = await ref.read(posProvider.notifier).lookupBuyer(_phone.text);
    if (!mounted) return;
    setState(() => _invalid = buyer == null);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final buyer = ref.watch(posProvider.select((s) => s.buyer));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.spaceScreenPadding,
        Tokens.space2,
        Tokens.spaceScreenPadding,
        Tokens.space2,
      ),
      child: buyer == null
          ? Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('pos-buyer-phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onSubmitted: (_) => _find(),
                    decoration: InputDecoration(
                      counterText: '',
                      prefixText: '${l10n.phonePrefix} ',
                      hintText: l10n.storeBuyerPhone,
                      helperText: l10n.storeBuyerWalkIn,
                      errorText: _invalid ? l10n.phoneInvalid : null,
                      prefixIcon: const Icon(Icons.person_search_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                AppButton(
                  key: const Key('pos-buyer-find'),
                  label: l10n.storeBuyerFind,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  expand: false,
                  onPressed: _find,
                ),
              ],
            )
          : Container(
              key: const Key('pos-buyer'),
              padding: const EdgeInsets.all(Tokens.space3),
              decoration: BoxDecoration(
                color: app.tint(app.palette.primaryContainer),
                borderRadius: BorderRadius.circular(Tokens.radiusCard),
                border: Border.fromBorderSide(app.borderSide),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    buyer.known ? Icons.person : Icons.person_add_alt,
                    color: app.palette.primary,
                  ),
                  const SizedBox(width: Tokens.space2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          buyer.name ?? l10n.storeBuyerUnknown,
                          style: app.text.label,
                        ),
                        Text(
                          '${l10n.phonePrefix} ${buyer.phone}',
                          style: app.text.caption.copyWith(
                            color: app.palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('pos-buyer-clear'),
                    onPressed: () {
                      _phone.clear();
                      ref.read(posProvider.notifier).clearBuyer();
                    },
                    child: Text(l10n.storeBuyerClear),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid({required this.items});

  final List<StoreItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final pos = ref.watch(posProvider);
    final q = pos.query.trim().toLowerCase();
    final shown = <StoreItem>[
      for (final i in items)
        if ((pos.category == null || i.category == pos.category) &&
            (q.isEmpty || matchesItem(i, q)))
          i,
    ];
    if (shown.isEmpty) {
      return EmptyState(
        key: const Key('pos-empty'),
        icon: Icons.search_off,
        title: l10n.storeNoProducts,
      );
    }
    final inCart = <String>{for (final l in pos.lines) l.item.skuId};
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 440 ? 2 : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 268,
            crossAxisSpacing: Tokens.space3,
            mainAxisSpacing: Tokens.space3,
          ),
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final item = shown[i];
            return ProductCard(
              key: Key('pos-product-${item.skuId}'),
              name: item.name,
              pack: item.packLabel,
              pricePaise: item.pricePaise,
              ownBrand: item.ownBrand,
              stockCount: item.stockQty?.floor(),
              storeName: ref.watch(activeStoreProvider)?.name,
              added: inCart.contains(item.skuId),
              onAdd: () => ref.read(posProvider.notifier).add(item),
            );
          },
        );
      },
    );
  }
}

/// Cart lines with qty steppers and the GST totals (S02 panel, S03 on
/// phones).
class CartPanel extends ConsumerWidget {
  /// Creates the panel.
  const CartPanel({this.showCheckout = false, super.key});

  /// Shows the checkout button (POS pane).
  final bool showCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final pos = ref.watch(posProvider);
    final notifier = ref.read(posProvider.notifier);
    final preview = pos.preview;
    return ColoredBox(
      color: p.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(Tokens.space4),
            child: Text(
              '${l10n.storeCartTitle} · ${l10n.cartItems(pos.itemCount)}',
              style: app.text.heading,
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: pos.lines.isEmpty
                ? EmptyState(
                    key: const Key('pos-cart-empty'),
                    icon: Icons.shopping_cart_outlined,
                    title: l10n.storeCartEmpty,
                    help: l10n.storeCartEmptyHelp,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space4,
                      vertical: Tokens.space2,
                    ),
                    itemCount: pos.lines.length,
                    separatorBuilder: (_, _) => Divider(color: p.border),
                    itemBuilder: (context, i) {
                      final line = pos.lines[i];
                      return Column(
                        key: Key('cart-line-${line.item.skuId}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(line.item.name, style: app.text.label),
                          Text(
                            '${line.item.packLabel} · ${formatInr(line.item.pricePaise)}',
                            style: app.text.caption.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                          Row(
                            children: <Widget>[
                              IconButton(
                                key: Key('cart-dec-${line.item.skuId}'),
                                tooltip: l10n.storeQtyDecrease,
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => notifier.setQty(
                                  line.item.skuId,
                                  line.qty - 1,
                                ),
                              ),
                              Text(
                                '${line.qty}',
                                key: Key('cart-qty-${line.item.skuId}'),
                                style: app.text.heading,
                              ),
                              IconButton(
                                key: Key('cart-inc-${line.item.skuId}'),
                                tooltip: l10n.storeQtyIncrease,
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => notifier.setQty(
                                  line.item.skuId,
                                  line.qty + 1,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatInr(line.taxablePaise),
                                key: Key('cart-total-${line.item.skuId}'),
                                style: app.text.label,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: p.border),
          Padding(
            padding: const EdgeInsets.all(Tokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                StoreAmountRow(
                  label: l10n.storeSubtotal,
                  value: formatInr(preview.taxablePaise),
                ),
                StoreAmountRow(
                  label: l10n.storeGst,
                  value: formatInr(preview.taxPaise),
                ),
                if (preview.roundOffPaise != 0)
                  StoreAmountRow(
                    label: l10n.storeRoundOff,
                    value: formatInr(preview.roundOffPaise),
                  ),
                StoreAmountRow(
                  key: const Key('cart-grand-total'),
                  label: l10n.storeTotal,
                  value: formatInr(preview.totalPaise),
                  strong: true,
                ),
                if (showCheckout) ...<Widget>[
                  const SizedBox(height: Tokens.space3),
                  AppButton(
                    key: const Key('pos-checkout'),
                    label: l10n.cartCheckout,
                    icon: Icons.arrow_forward,
                    onPressed: pos.lines.isEmpty
                        ? null
                        : () => context.push(StoreRoutes.checkout),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
