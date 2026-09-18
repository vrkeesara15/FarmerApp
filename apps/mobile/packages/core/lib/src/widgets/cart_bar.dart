import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../utils/format.dart';
import 'app_button.dart';

/// Sticky bottom cart summary with a checkout button
/// (SPEC 13.1 `CartBar`).
class CartBar extends StatelessWidget {
  /// Creates the bar.
  const CartBar({
    required this.itemCount,
    required this.totalPaise,
    required this.onCheckout,
    this.actionLabel,
    this.estimate = false,
    super.key,
  });

  /// Number of line items.
  final int itemCount;

  /// Cart total in paise.
  final int totalPaise;

  /// Checkout handler; `null` disables the button.
  final VoidCallback? onCheckout;

  /// Override for the button label (defaults to "Checkout").
  final String? actionLabel;

  /// The total is an estimate from cached prices (FA-020: the server
  /// prices the order).
  final bool estimate;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: app.borderSide),
        boxShadow: app.isSunlight
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: Tokens.elevationSheet.color,
                  blurRadius: Tokens.elevationSheet.blur,
                  offset: Offset(
                    Tokens.elevationSheet.offsetX,
                    -Tokens.elevationSheet.offsetY,
                  ),
                ),
              ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: Tokens.space4,
                        color: p.textSecondary,
                      ),
                      const SizedBox(width: Tokens.space1),
                      Text(
                        l10n.cartItems(itemCount),
                        style: app.text.caption.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${estimate ? l10n.cartEstimatedTotal : l10n.cartTotal} '
                    '${formatInr(totalPaise)}',
                    style: app.text.heading,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Tokens.space3),
            Expanded(
              child: AppButton(
                label: actionLabel ?? l10n.cartCheckout,
                icon: Icons.arrow_forward,
                onPressed: onCheckout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
