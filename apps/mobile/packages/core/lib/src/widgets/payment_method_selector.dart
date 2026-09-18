import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Payment methods offered at checkout (SPEC A52 / F32).
enum PaymentMethod {
  /// Show a UPI QR to scan.
  upiQr,

  /// Send a payment link by SMS/WhatsApp.
  paymentLink,

  /// Cash with receipt.
  cash,

  /// Add to farmer khata.
  credit,
}

/// Large radio-style list of payment methods
/// (SPEC 13.1 `PaymentMethodSelector`).
class PaymentMethodSelector extends StatelessWidget {
  /// Creates the selector.
  const PaymentMethodSelector({
    required this.selected,
    required this.onChanged,
    this.available = const <PaymentMethod>{
      PaymentMethod.upiQr,
      PaymentMethod.paymentLink,
      PaymentMethod.cash,
      PaymentMethod.credit,
    },
    this.creditHint,
    this.unavailableReasons = const <PaymentMethod, String>{},
    super.key,
  });

  /// Selected method.
  final PaymentMethod? selected;

  /// Selection handler; `null` disables all options.
  final ValueChanged<PaymentMethod>? onChanged;

  /// Methods that can be chosen; others render disabled.
  final Set<PaymentMethod> available;

  /// Override for the credit hint (e.g. "Limit ₹5,000 left").
  final String? creditHint;

  /// Why a method is not available (e.g. "Needs internet"); replaces the
  /// hint of a disabled option.
  final Map<PaymentMethod, String> unavailableReasons;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return Column(
      children: <Widget>[
        for (final m in PaymentMethod.values) ...<Widget>[
          _Option(
            key: Key('payment-method-${m.name}'),
            method: m,
            title: switch (m) {
              PaymentMethod.upiQr => l10n.paymentUpiQr,
              PaymentMethod.paymentLink => l10n.paymentLink,
              PaymentMethod.cash => l10n.paymentCash,
              PaymentMethod.credit => l10n.paymentCredit,
            },
            hint: !available.contains(m) && unavailableReasons[m] != null
                ? unavailableReasons[m]!
                : switch (m) {
                    PaymentMethod.upiQr => l10n.paymentUpiQrHint,
                    PaymentMethod.paymentLink => l10n.paymentLinkHint,
                    PaymentMethod.cash => l10n.paymentCashHint,
                    PaymentMethod.credit =>
                      creditHint ?? l10n.paymentCreditHint,
                  },
            icon: switch (m) {
              PaymentMethod.upiQr => Icons.qr_code_2,
              PaymentMethod.paymentLink => Icons.link,
              PaymentMethod.cash => Icons.payments_outlined,
              PaymentMethod.credit => Icons.menu_book_outlined,
            },
            selected: m == selected,
            enabled: onChanged != null && available.contains(m),
            onTap: () => onChanged?.call(m),
          ),
          if (m != PaymentMethod.values.last)
            const SizedBox(height: Tokens.space2),
        ],
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.method,
    required this.title,
    required this.hint,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final PaymentMethod method;
  final String title;
  final String hint;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final fg = enabled ? p.text : p.textMuted;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      label: title,
      child: Material(
        color: selected ? app.tint(p.primaryContainer) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: BorderSide(
            color: selected ? p.primary : p.border,
            width: selected ? app.borderWidth + 1 : app.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Tokens.sizePrimaryButtonHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.all(Tokens.space3),
              child: Row(
                children: <Widget>[
                  Icon(icon, color: enabled ? p.primary : p.textMuted),
                  const SizedBox(width: Tokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: app.text.body.copyWith(color: fg)),
                        Text(
                          hint,
                          style: app.text.caption.copyWith(
                            color: enabled ? p.textSecondary : p.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Tokens.space2),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? p.primary : p.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
