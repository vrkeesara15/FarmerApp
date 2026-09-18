import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/commerce_copy.dart';

/// A55 Cash receipt capture (FA-021): in-app camera photo of the receipt
/// through the NF-004 pipeline, then a `payment` create op with the
/// receipt upload (works offline). The payment is "pending store
/// reconciliation" until the store's day close.
class CashScreen extends ConsumerStatefulWidget {
  /// Creates the screen for an order, or for dues ([amountPaise] at
  /// [storeId]).
  const CashScreen({
    this.orderId,
    this.farmerId,
    this.storeId,
    this.amountPaise,
    super.key,
  });

  /// Order paid for.
  final String? orderId;

  /// Farmer (dues).
  final String? farmerId;

  /// Store (dues).
  final String? storeId;

  /// Dues amount.
  final int? amountPaise;

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  PendingReceipt? _receipt;
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    final receipt = await ref.read(receiptCaptureProvider)();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (receipt != null) _receipt = receipt;
    });
  }

  Future<void> _save(OrderView? order) async {
    final receipt = _receipt;
    if (receipt == null) return;
    setState(() => _busy = true);
    final repo = ref.read(paymentRepositoryProvider);
    final l10n = CoreLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final PaymentTarget target;
    final int expected;
    if (widget.orderId != null) {
      target = PaymentTarget.order(
        orderId: widget.orderId!,
        farmerId: order?.order.farmerId,
        storeId: order?.order.storeId,
      );
      expected = order?.displayTotalPaise ?? 0;
    } else {
      target = PaymentTarget.dues(
        farmerId: widget.farmerId!,
        storeId: widget.storeId!,
        duesAmountPaise: widget.amountPaise!,
      );
      expected = widget.amountPaise!;
    }
    await repo.collectCash(
      target,
      receiptJpeg: receipt.bytes,
      expectedPaise: expected,
    );
    await syncIfOnline(ref);
    messenger.showSnackBar(SnackBar(content: Text(l10n.cashSaved)));
    if (widget.orderId != null) {
      refreshOrder(ref, widget.orderId!);
      router.go(CommerceRoutes.order(widget.orderId!));
    } else {
      router.go(CommerceRoutes.khata(widget.farmerId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final order = widget.orderId == null
        ? null
        : ref.watch(orderViewProvider(widget.orderId!)).value;
    final amount = widget.amountPaise ?? order?.displayTotalPaise ?? 0;
    final farmerId = widget.farmerId ?? order?.order.farmerId;
    final receipt = _receipt;
    final bad = receipt != null && !receipt.quality.isAcceptable;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cashTitle)),
      bottomNavigationBar: BottomActions(
        children: <Widget>[
          if (receipt == null)
            AppButton(
              key: const Key('cash-capture'),
              label: l10n.cashTakePhoto,
              icon: Icons.photo_camera_outlined,
              loading: _busy,
              onPressed: _busy ? null : _capture,
            )
          else ...<Widget>[
            AppButton(
              key: const Key('cash-retake'),
              label: l10n.cashRetake,
              icon: Icons.refresh,
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : _capture,
            ),
            AppButton(
              key: const Key('cash-save'),
              label: l10n.cashSave,
              icon: Icons.check,
              loading: _busy,
              onPressed: _busy || bad ? null : () => _save(order),
            ),
          ],
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  if (farmerId != null)
                    Text(
                      l10n.catalogForFarmer(farmerNameOf(ref, farmerId)),
                      style: app.text.heading,
                    ),
                  const SizedBox(height: Tokens.space2),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Tokens.space3),
                      child: MoneyRow(
                        key: const Key('cash-amount'),
                        label: l10n.cashAmount,
                        paise: amount,
                        strong: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: Tokens.space3),
                  Text(
                    l10n.cashPhotoHelp,
                    style: app.text.body.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: Tokens.space3),
                  if (receipt != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Tokens.radiusCard),
                      child: Image.memory(
                        receipt.bytes,
                        key: const Key('cash-preview'),
                        height: 240,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    )
                  else
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: app.tint(p.background),
                        borderRadius: BorderRadius.circular(Tokens.radiusCard),
                        border: Border.fromBorderSide(app.borderSide),
                      ),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        size: Tokens.space12,
                        color: p.textMuted,
                      ),
                    ),
                  if (bad) ...<Widget>[
                    const SizedBox(height: Tokens.space2),
                    Text(
                      l10n.cashPhotoBad,
                      key: const Key('cash-photo-bad'),
                      style: app.text.body.copyWith(color: p.statusDanger),
                    ),
                  ],
                  const SizedBox(height: Tokens.space3),
                  Row(
                    children: <Widget>[
                      Icon(Icons.info_outline, color: p.statusInfo),
                      const SizedBox(width: Tokens.space2),
                      Expanded(
                        child: Text(
                          l10n.cashPendingReconciliation,
                          style: app.text.label.copyWith(color: p.statusInfo),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
