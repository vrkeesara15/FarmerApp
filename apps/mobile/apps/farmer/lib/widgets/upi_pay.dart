import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How a UPI payment ended.
enum UpiOutcome {
  /// The server marked it paid (webhook).
  paid,

  /// Failed or expired at the provider.
  failed,

  /// The farmer gave up (Cancel).
  cancelled,

  /// No network to create the payment.
  offline,
}

/// The paid payment (for the F51 receipt).
@immutable
class UpiResult {
  /// Creates the result.
  const UpiResult(
    this.outcome, {
    this.paymentId,
    this.amountPaise,
    this.paidAt,
  });

  /// Outcome.
  final UpiOutcome outcome;

  /// Payment id.
  final String? paymentId;

  /// Amount charged.
  final int? amountPaise;

  /// When it was paid (UTC).
  final DateTime? paidAt;
}

/// FM-010 pay by UPI: creates a UPI payment for [target] (`order_id`, or
/// `farmer_id` + `store_id` + `amount_paise` for dues), opens the phone's
/// UPI apps with the payment intent (`upi://pay?...` from the payments
/// API) and waits on a sheet while polling `GET /v1/payments/{id}` until
/// the webhook marks it paid, it fails or the farmer cancels.
Future<UpiResult> payByUpi(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> target,
) async {
  final api = ref.read(paymentsApiProvider);
  final created = await api.create(<String, Object?>{
    ...target,
    'mode': PaymentModes.upiQr,
  });
  if (created.result == PaymentCallResult.network) {
    return const UpiResult(UpiOutcome.offline);
  }
  if (created.result != PaymentCallResult.ok) {
    return const UpiResult(UpiOutcome.failed);
  }
  final body = created.body;
  final paymentId = '${body['payment_id']}';
  final link = (body['qr_payload'] ?? body['short_url']) as String?;
  final amount = (body['amount_paise'] as num?)?.toInt();
  if (!context.mounted) return const UpiResult(UpiOutcome.cancelled);
  final outcome = await showModalBottomSheet<UpiOutcome>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _UpiWaitingSheet(
      paymentId: paymentId,
      link: link,
      amountPaise: amount,
      expiresAt: DateTime.tryParse('${body['expires_at']}')?.toUtc(),
    ),
  );
  return UpiResult(
    outcome ?? UpiOutcome.cancelled,
    paymentId: paymentId,
    amountPaise: amount,
    paidAt: outcome == UpiOutcome.paid ? ref.read(clockProvider)() : null,
  );
}

class _UpiWaitingSheet extends ConsumerStatefulWidget {
  const _UpiWaitingSheet({
    required this.paymentId,
    required this.link,
    required this.amountPaise,
    required this.expiresAt,
  });

  final String paymentId;
  final String? link;
  final int? amountPaise;
  final DateTime? expiresAt;

  @override
  ConsumerState<_UpiWaitingSheet> createState() => _UpiWaitingSheetState();
}

class _UpiWaitingSheetState extends ConsumerState<_UpiWaitingSheet> {
  StreamSubscription<UpiPollState>? _sub;
  bool _noApp = false;

  @override
  void initState() {
    super.initState();
    _openApp();
    final api = ref.read(paymentsApiProvider);
    final poller = UpiPoller(
      fetch: () => api.status(widget.paymentId),
      clock: ref.read(clockProvider),
      sleep: ref.read(upiSleepProvider),
      expiresAt: widget.expiresAt,
    );
    _sub = poller.run().listen((s) {
      if (!s.isFinal || !mounted) return;
      Navigator.of(
        context,
      ).pop(s.phase == UpiPollPhase.paid ? UpiOutcome.paid : UpiOutcome.failed);
    });
  }

  Future<void> _openApp() async {
    final link = widget.link;
    final ok = link != null && await ref.read(urlOpenerProvider).open(link);
    if (mounted) setState(() => _noApp = !ok);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return SafeArea(
      child: Padding(
        key: const Key('upi-waiting'),
        padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.amountPaise != null)
              Text(
                formatInr(widget.amountPaise!),
                textAlign: TextAlign.center,
                style: app.text.display,
              ),
            const SizedBox(height: Tokens.space2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox.square(
                  dimension: Tokens.space6,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: Tokens.space3),
                Flexible(
                  child: Text(l10n.kisanUpiWaiting, style: app.text.heading),
                ),
              ],
            ),
            if (_noApp) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              Text(
                l10n.kisanUpiNoApp,
                key: const Key('upi-no-app'),
                textAlign: TextAlign.center,
                style: app.text.body.copyWith(color: app.palette.statusDanger),
              ),
            ],
            const SizedBox(height: Tokens.space4),
            AppButton(
              key: const Key('upi-open-again'),
              label: l10n.kisanUpiOpenAgain,
              icon: Icons.open_in_new,
              variant: AppButtonVariant.secondary,
              onPressed: _openApp,
            ),
            AppButton(
              key: const Key('upi-cancel'),
              label: l10n.actionCancel,
              variant: AppButtonVariant.tertiary,
              onPressed: () => Navigator.of(context).pop(UpiOutcome.cancelled),
            ),
          ],
        ),
      ),
    );
  }
}
