import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../utils/format.dart';
import 'app_button.dart';
import 'own_brand_badge.dart';

/// Catalogue product with image, pack, price, own-brand badge, stock at the
/// nearest store and an add button (SPEC 13.1 `ProductCard`).
class ProductCard extends StatelessWidget {
  /// Creates the card.
  const ProductCard({
    required this.name,
    required this.pack,
    required this.pricePaise,
    this.image,
    this.ownBrand = false,
    this.stockCount,
    this.storeName,
    this.added = false,
    this.onAdd,
    this.onTap,
    this.stockAsOf,
    this.priceIsEstimate = false,
    this.quantity,
    this.actionLabel,
    this.actionIcon,
    this.showAction = true,
    this.actionKey,
    super.key,
  });

  /// Product name.
  final String name;

  /// Pack size, e.g. `250 ml`.
  final String pack;

  /// Price in paise.
  final int pricePaise;

  /// Product image.
  final ImageProvider<Object>? image;

  /// Shows the [OwnBrandBadge].
  final bool ownBrand;

  /// Units in stock at [storeName]; `0` shows out of stock; `null` hides.
  final int? stockCount;

  /// Nearest store name.
  final String? storeName;

  /// Whether the item is already in the cart.
  final bool added;

  /// Add-to-cart handler; `null` disables the button.
  final VoidCallback? onAdd;

  /// Card tap handler (opens detail).
  final VoidCallback? onTap;

  /// When the stock figure was true (UTC); shows "as of HH:mm".
  final DateTime? stockAsOf;

  /// Labels the price as an estimate (cached price list, FA-020).
  final bool priceIsEstimate;

  /// Units already in the cart (shown on the added button).
  final int? quantity;

  /// Label of the action button instead of "Add" (e.g. "Order" on a
  /// diagnosis result).
  final String? actionLabel;

  /// Icon of the action button instead of the cart.
  final IconData? actionIcon;

  /// False hides the action button entirely (SPEC 3.4: a provisional
  /// diagnosis never shows a buy button).
  final bool showAction;

  /// Key of the action button (tests).
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final outOfStock = stockCount == 0;

    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: app.borderSide,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: Tokens.space12 + Tokens.space6,
                height: Tokens.space12 + Tokens.space6,
                decoration: BoxDecoration(
                  color: app.tint(p.background),
                  borderRadius: BorderRadius.circular(Tokens.radiusInput),
                  border: Border.fromBorderSide(app.borderSide),
                  image: image == null
                      ? null
                      : DecorationImage(image: image!, fit: BoxFit.cover),
                ),
                child: image == null
                    ? Icon(Icons.inventory_2_outlined, color: p.textMuted)
                    : null,
              ),
              const SizedBox(width: Tokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (ownBrand) ...<Widget>[
                      const OwnBrandBadge(),
                      const SizedBox(height: Tokens.space1),
                    ],
                    Text(
                      name,
                      style: app.text.heading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${l10n.productPack}: $pack',
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: Tokens.space1),
                    Text(formatInr(pricePaise), style: app.text.title),
                    if (priceIsEstimate)
                      Text(
                        l10n.productPriceEstimate,
                        style: app.text.caption.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    if (stockCount != null) ...<Widget>[
                      const SizedBox(height: Tokens.space1),
                      Row(
                        children: <Widget>[
                          Icon(
                            outOfStock
                                ? Icons.remove_shopping_cart_outlined
                                : Icons.store_outlined,
                            size: Tokens.space4,
                            color: outOfStock
                                ? p.statusDanger
                                : p.statusSuccess,
                          ),
                          const SizedBox(width: Tokens.space1),
                          Expanded(
                            child: Text(
                              <String>[
                                if (outOfStock)
                                  l10n.productOutOfStock
                                else if (storeName == null ||
                                    storeName!.isEmpty)
                                  l10n.productStockNearest(stockCount!)
                                else
                                  l10n.productStockAtStore(
                                    stockCount!,
                                    storeName!,
                                  ),
                                if (stockAsOf != null)
                                  l10n.productStockAsOf(
                                    formatTimeIst(stockAsOf!),
                                  ),
                              ].join(', '),
                              style: app.text.caption.copyWith(
                                color: outOfStock
                                    ? p.statusDanger
                                    : p.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (showAction) ...<Widget>[
                      const SizedBox(height: Tokens.space2),
                      AppButton(
                        key: actionKey,
                        label: actionLabel != null
                            ? actionLabel!
                            : added
                            ? (quantity == null
                                  ? l10n.productAdded
                                  : l10n.productInCart(quantity!))
                            : l10n.productAdd,
                        icon:
                            actionIcon ??
                            (added ? Icons.check : Icons.add_shopping_cart),
                        variant: added
                            ? AppButtonVariant.secondary
                            : AppButtonVariant.primary,
                        size: AppButtonSize.medium,
                        expand: false,
                        onPressed: outOfStock ? null : onAdd,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
