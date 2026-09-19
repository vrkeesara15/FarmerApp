import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/kisan_widgets.dart';
import '../widgets/upi_pay.dart';
import 'payment_receipt_screen.dart';

/// F50 Khata (FM-010): balance, due date, history and "Pay now" by UPI.
/// After the payment shows paid the khata is fetched again at once (the
/// server moves the balance in the webhook transaction, FA-021) and F51
/// shows the receipt with the new balance. Cached for offline viewing.
class KhataScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const KhataScreen({super.key});

  @override
  ConsumerState<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends ConsumerState<KhataScreen> {
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final id = await ref.read(kisanFarmerIdProvider.future);
    if (id != null) await ref.read(khataRepositoryProvider).refresh(id);
  }

  Future<void> _pay(String farmerId, KhataView khata) async {
    final l10n = CoreLocalizations.of(context);
    final storeId = khata.collectStoreId;
    if (storeId == null) return;
    setState(() => _paying = true);
    final result = await payByUpi(context, ref, <String, Object?>{
      'farmer_id': farmerId,
      'store_id': storeId,
      'amount_paise': khata.balanceAt(storeId),
    });
    if (result.outcome == UpiOutcome.paid) {
      final repo = ref.read(khataRepositoryProvider);
      await repo.refresh(farmerId);
      final fresh = await repo.read(farmerId);
      if (!mounted) return;
      setState(() => _paying = false);
      context.go(
        AppRoutes.receipt,
        extra: PaymentReceipt(
          paymentId: result.paymentId!,
          amountPaise: result.amountPaise ?? khata.balanceAt(storeId),
          paidAt: result.paidAt ?? ref.read(clockProvider)(),
          balanceAfterPaise: fresh?.balancePaise,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _paying = false);
    showKisanMessage(context, switch (result.outcome) {
      UpiOutcome.offline => l10n.kisanNeedsInternet,
      UpiOutcome.failed => l10n.kisanPaymentFailed,
      _ => l10n.kisanNotPaidYet,
    });
  }

  String _describe(CoreLocalizations l10n, KhataLine e) => switch (e.refType) {
    'order' => l10n.khataEntryOrder,
    'payment' => l10n.khataEntryPayment,
    _ => l10n.khataEntryAdjustment,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final farmerId = ref.watch(kisanFarmerIdProvider).value;
    final khata = farmerId == null ? null : ref.watch(khataProvider(farmerId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.khataTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: khata == null || khata.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : khata.value == null
                  ? EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: l10n.kisanKhataNotLoaded,
                      help: l10n.kisanNeedsInternet,
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.all(
                          Tokens.spaceScreenPadding,
                        ),
                        children: <Widget>[
                          if (khata.value!.overduePaise > 0)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: Tokens.space2,
                              ),
                              child: Text(
                                l10n.khataOverdue(
                                  formatInr(khata.value!.overduePaise),
                                ),
                                style: app.text.heading.copyWith(
                                  color: app.palette.statusDanger,
                                ),
                              ),
                            ),
                          KhataLedger(
                            key: const Key('khata-ledger'),
                            balancePaise: khata.value!.balancePaise,
                            dueDateUtc: khata.value!.nextDueDate,
                            now: ref.watch(clockProvider)(),
                            actionLabel: l10n.khataPayNow,
                            onAction:
                                khata.value!.balancePaise > 0 &&
                                    khata.value!.collectStoreId != null &&
                                    !_paying
                                ? () => _pay(farmerId!, khata.value!)
                                : null,
                            entries: <KhataEntry>[
                              for (final e in khata.value!.entries)
                                KhataEntry(
                                  dateUtc: e.createdAt,
                                  description: _describe(l10n, e),
                                  amountPaise: e.amountPaise,
                                  isCredit: !e.isDebit,
                                  dueDateUtc: e.dueDate,
                                  harvestMonthUtc: e.harvestMonth,
                                ),
                            ],
                          ),
                          const SizedBox(height: Tokens.space2),
                          AsOfLabel(khata.value!.asOf),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
