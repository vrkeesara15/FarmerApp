import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';
import 'shop_screen.dart';

/// F30 Product detail: name in the farmer's language, pack, price at the
/// farmer's store, own-brand badge, stock, and two decisions: how many
/// and "Add to cart".
class ProductDetailScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ProductDetailScreen({required this.skuId, super.key});

  /// SKU shown.
  final String skuId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int? _qty;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final item = ref.watch(kisanItemProvider(widget.skuId));
    final inCart = ref.watch(cartProvider).qtyOf(widget.skuId);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanProductTitle)),
      body: SafeArea(
        child: item.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const ErrorState(),
          data: (it) {
            if (it == null) {
              return EmptyState(
                icon: Icons.inventory_2_outlined,
                title: l10n.catalogNeverLoaded,
                help: l10n.catalogNeverLoadedHelp,
              );
            }
            final qty = _qty ?? (inCart > 0 ? inCart : 1);
            final units = it.stock?.wholeUnits;
            return Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    children: <Widget>[
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          color: app.tint(p.primaryContainer),
                          borderRadius: BorderRadius.circular(
                            Tokens.radiusCard,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: p.primary,
                        ),
                      ),
                      const SizedBox(height: Tokens.space3),
                      Text(
                        it.nameIn(lang),
                        key: const Key('product-name'),
                        style: app.text.title,
                      ),
                      Text(
                        '${it.brand} · ${it.packLabel}',
                        style: app.text.body.copyWith(color: p.textSecondary),
                      ),
                      if (it.ownBrand) ...<Widget>[
                        const SizedBox(height: Tokens.space2),
                        const Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OwnBrandBadge(),
                        ),
                      ],
                      const SizedBox(height: Tokens.space3),
                      Text(
                        formatInr(it.pricePaise),
                        key: const Key('product-price'),
                        style: app.text.display,
                      ),
                      if (units != null)
                        Text(
                          units > 0
                              ? l10n.kisanInStock('$units')
                              : l10n.kisanOutOfStock,
                          style: app.text.body.copyWith(
                            color: units > 0 ? p.statusSuccess : p.statusDanger,
                          ),
                        ),
                      const SizedBox(height: Tokens.space4),
                      SpokenText(
                        promptId: 'f30_how_many',
                        text: l10n.kisanHowMany,
                        style: app.text.heading,
                      ),
                      QtyStepper(
                        qty: qty,
                        keyPrefix: 'product-qty',
                        onChanged: (v) => setState(() => _qty = v),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                  child: AppButton(
                    key: const Key('product-add'),
                    label: l10n.kisanAddToCart,
                    icon: Icons.add_shopping_cart,
                    onPressed: qty <= 0
                        ? null
                        : () {
                            ref.read(cartProvider.notifier).setQty(it, qty);
                            context.pushReplacement(AppRoutes.cart);
                          },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
