import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

/// What F51 shows.
@immutable
class PaymentReceipt {
  /// Creates the receipt.
  const PaymentReceipt({
    required this.paymentId,
    required this.amountPaise,
    required this.paidAt,
    this.balanceAfterPaise,
  });

  /// Payment id (reference).
  final String paymentId;

  /// Amount paid.
  final int amountPaise;

  /// When (UTC).
  final DateTime paidAt;

  /// Khata balance after the payment, as fetched right after.
  final int? balanceAfterPaise;
}

/// F51 Payment success receipt (FM-010): amount, date, reference and the
/// khata balance after the payment.
class PaymentReceiptScreen extends StatelessWidget {
  /// Creates the screen.
  const PaymentReceiptScreen({required this.receipt, super.key});

  /// The receipt; null when opened without one (goes back to the khata).
  final PaymentReceipt? receipt;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final r = receipt;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanReceiptTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: Tokens.space6),
              Icon(Icons.check_circle, size: 96, color: p.statusSuccess),
              const SizedBox(height: Tokens.space3),
              Text(
                l10n.kisanPaymentDone,
                textAlign: TextAlign.center,
                style: app.text.title,
              ),
              if (r != null) ...<Widget>[
                const SizedBox(height: Tokens.space2),
                Text(
                  formatInr(r.amountPaise),
                  key: const Key('receipt-amount'),
                  textAlign: TextAlign.center,
                  style: app.text.display,
                ),
                const SizedBox(height: Tokens.space4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Tokens.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.kisanPaidOn(formatDateTimeIst(r.paidAt)),
                          style: app.text.body,
                        ),
                        Text(
                          l10n.kisanPaymentRef(r.paymentId),
                          style: app.text.body,
                        ),
                        if (r.balanceAfterPaise != null)
                          Text(
                            l10n.kisanBalanceNow(
                              formatInr(r.balanceAfterPaise!),
                            ),
                            key: const Key('receipt-balance'),
                            style: app.text.heading,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              AppButton(
                key: const Key('receipt-done'),
                label: l10n.actionDone,
                icon: Icons.home_outlined,
                onPressed: () => context.go(AppRoutes.home),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
