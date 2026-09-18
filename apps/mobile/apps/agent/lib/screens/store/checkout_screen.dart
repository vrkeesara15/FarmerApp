import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'gst_invoice_view.dart';
import 'pos_screen.dart';
import 'store_routes.dart';
import 'store_shell.dart';

/// S03 Checkout: payment method (UPI QR with polling, card on the store
/// terminal with a reference, cash with change, credit within the limit),
/// the GST invoice preview, and the sale. The network is required to
/// finalise; offline and refused sales keep the cart.
class CheckoutScreen extends ConsumerWidget {
  /// Creates the screen.
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final pos = ref.watch(posProvider);
    ref.listen<CheckoutPhase>(posProvider.select((s) => s.phase), (_, next) {
      final sale = ref.read(posProvider).sale;
      if (next == CheckoutPhase.done && sale != null) {
        context.go(StoreRoutes.invoice(sale.invoice.id));
      }
    });
    final twoPane = isStoreTwoPane(context);
    final preview = StoreCard(
      key: const Key('checkout-preview'),
      title: l10n.storeInvoicePreview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GstInvoiceView.preview(pos.preview),
          const SizedBox(height: Tokens.space2),
          Text(
            l10n.storeInvoicePreviewNote,
            style: context.app.text.caption.copyWith(
              color: context.app.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
    const payment = _PaymentPane();
    return StoreShell(
      section: StoreSection.pos,
      title: l10n.storeCheckoutTitle,
      showBack: true,
      body: pos.lines.isEmpty && pos.sale == null
          ? EmptyState(
              icon: Icons.shopping_cart_outlined,
              title: l10n.storeCartEmpty,
              help: l10n.storeCartEmptyHelp,
              actionLabel: l10n.storeNavPos,
              onAction: () => context.go(StoreRoutes.pos),
            )
          : twoPane
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    children: const <Widget>[payment],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    children: <Widget>[preview],
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              children: <Widget>[
                const SizedBox(height: 360, child: CartPanel()),
                const SizedBox(height: Tokens.space4),
                preview,
                const SizedBox(height: Tokens.space4),
                payment,
              ],
            ),
    );
  }
}

class _PaymentPane extends ConsumerStatefulWidget {
  const _PaymentPane();

  @override
  ConsumerState<_PaymentPane> createState() => _PaymentPaneState();
}

class _PaymentPaneState extends ConsumerState<_PaymentPane> {
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _tendered = TextEditingController();

  @override
  void initState() {
    super.initState();
    final pos = ref.read(posProvider);
    _reference.text = pos.cardReference;
    if (pos.tenderedPaise != null) {
      _tendered.text = formatInr(
        pos.tenderedPaise!,
        showPaise: false,
      ).replaceAll(rupeeSign, '').replaceAll(',', '');
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _tendered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final pos = ref.watch(posProvider);
    final notifier = ref.read(posProvider.notifier);
    final locked =
        pos.phase == CheckoutPhase.submitting ||
        pos.phase == CheckoutPhase.awaitingUpi ||
        pos.phase == CheckoutPhase.upiFailed;
    final upiActive =
        pos.phase == CheckoutPhase.awaitingUpi ||
        pos.phase == CheckoutPhase.upiFailed;
    final children = <Widget>[
      if (upiActive) ...<Widget>[
        _PhasePanel(state: pos),
        const SizedBox(height: Tokens.space4),
      ],
      StoreCard(
        title: l10n.storePayWith,
        child: StoreModeSelector(
          selected: pos.mode,
          onChanged: locked ? null : notifier.setMode,
          creditEnabled: pos.buyer?.known ?? false,
        ),
      ),
      const SizedBox(height: Tokens.space4),
    ];
    switch (pos.mode) {
      case SaleMode.card:
        children.add(
          AppTextField(
            key: const Key('checkout-card-ref'),
            label: l10n.storeCardReference,
            hintText: l10n.storeCardReferenceHint,
            controller: _reference,
            enabled: !locked,
            errorText: pos.phase == CheckoutPhase.referenceRequired
                ? l10n.storeCardReferenceRequired
                : null,
            onChanged: notifier.setCardReference,
          ),
        );
      case SaleMode.cash:
        final change = pos.changePaise;
        children.addAll(<Widget>[
          AppTextField(
            key: const Key('checkout-cash-tendered'),
            label: l10n.storeCashTendered,
            controller: _tendered,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !locked,
            prefixIcon: Icons.currency_rupee,
            errorText: pos.phase == CheckoutPhase.cashShort
                ? l10n.storeCashShort
                : null,
            onChanged: (v) => notifier.setTendered(parseRupees(v)),
          ),
          const SizedBox(height: Tokens.space2),
          if (change != null && change >= 0)
            StoreAmountRow(
              key: const Key('checkout-change'),
              label: l10n.storeCashChange,
              value: formatInr(change),
              strong: true,
              color: p.statusSuccess,
            ),
        ]);
      case SaleMode.credit:
        if (!(pos.buyer?.known ?? false)) {
          children.add(
            Text(
              l10n.storeCreditNeedsFarmer,
              style: app.text.body.copyWith(color: p.statusWarning),
            ),
          );
        }
      case SaleMode.upiQr:
      case null:
        break;
    }
    if (!upiActive) {
      children
        ..add(const SizedBox(height: Tokens.space4))
        ..add(_PhasePanel(state: pos));
    }
    if (!locked || pos.phase == CheckoutPhase.submitting) {
      children.addAll(<Widget>[
        const SizedBox(height: Tokens.space4),
        AppButton(
          key: const Key('checkout-confirm'),
          label: l10n.storeConfirmSale,
          icon: Icons.check,
          loading: pos.phase == CheckoutPhase.submitting,
          onPressed: pos.mode == null || pos.lines.isEmpty
              ? null
              : notifier.confirm,
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _PhasePanel extends ConsumerWidget {
  const _PhasePanel({required this.state});

  final PosState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final notifier = ref.read(posProvider.notifier);
    Widget banner(
      Key key,
      Color color,
      IconData icon,
      String title,
      String help, [
      List<Widget> extra = const <Widget>[],
    ]) => Container(
      key: key,
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: app.tint(p.surface),
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.all(color: color, width: app.borderWidth + 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Text(
                  title,
                  style: app.text.heading.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.space2),
          Text(help, style: app.text.body),
          ...extra,
        ],
      ),
    );
    switch (state.phase) {
      case CheckoutPhase.offline:
        return banner(
          const Key('checkout-offline'),
          p.statusWarning,
          Icons.cloud_off_outlined,
          l10n.storeOfflineSaleTitle,
          l10n.storeOfflineSaleHelp,
        );
      case CheckoutPhase.approvalNeeded:
        final f = state.failure!;
        return banner(
          const Key('checkout-approval'),
          p.statusDanger,
          Icons.gpp_maybe_outlined,
          l10n.storeApprovalNeededTitle,
          l10n.storeApprovalNeededHelp(
            formatInr(f.intExtra('shortfall_paise')),
          ),
          <Widget>[
            const SizedBox(height: Tokens.space2),
            StoreAmountRow(
              label: l10n.storeCreditBalance,
              value: formatInr(f.intExtra('balance_paise')),
            ),
            StoreAmountRow(
              label: l10n.storeCreditLimit,
              value: formatInr(f.intExtra('limit_paise')),
            ),
            const SizedBox(height: Tokens.space2),
            AppButton(
              key: const Key('checkout-other-mode'),
              label: l10n.storeChooseAnotherMode,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              onPressed: notifier.backToEditing,
            ),
          ],
        );
      case CheckoutPhase.failed:
        return banner(
          const Key('checkout-failed'),
          p.statusDanger,
          Icons.error_outline,
          l10n.storeSaleFailedTitle,
          state.failure?.code == 'farmer_required'
              ? l10n.storeCreditNeedsFarmer
              : l10n.storeSaleFailed(state.failure?.code ?? ''),
        );
      case CheckoutPhase.awaitingUpi:
      case CheckoutPhase.upiFailed:
        final pay = state.upiPayment!;
        final now = ref.watch(clockProvider)();
        final remaining = pay.expiresAt?.difference(now);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            UpiQrPanel(
              key: const Key('checkout-upi'),
              state: state.phase == CheckoutPhase.awaitingUpi
                  ? UpiPaymentState.waiting
                  : UpiPaymentState.failed,
              amountPaise: state.sale?.invoice.totalPaise ?? pay.amountPaise,
              qrPayload: pay.qrPayload ?? '',
              remaining: remaining == null || remaining.isNegative
                  ? null
                  : remaining,
              onRetry: notifier.retryUpi,
            ),
            if (state.sale != null) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              Text(
                l10n.storeInvoiceNo(state.sale!.invoice.invoiceNo),
                textAlign: TextAlign.center,
                style: app.text.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ],
        );
      case CheckoutPhase.editing:
      case CheckoutPhase.submitting:
      case CheckoutPhase.referenceRequired:
      case CheckoutPhase.cashShort:
      case CheckoutPhase.done:
        return const SizedBox.shrink();
    }
  }
}

/// Counter payment modes: UPI QR, card on the terminal, cash, credit.
/// (The shared `PaymentMethodSelector` has no card-terminal option; this
/// keeps its look.)
class StoreModeSelector extends StatelessWidget {
  /// Creates the selector.
  const StoreModeSelector({
    required this.selected,
    required this.onChanged,
    this.creditEnabled = true,
    super.key,
  });

  /// Selected mode.
  final SaleMode? selected;

  /// Handler; null disables.
  final ValueChanged<SaleMode>? onChanged;

  /// Credit needs a known farmer.
  final bool creditEnabled;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Column(
      children: <Widget>[
        for (final m in SaleMode.values) ...<Widget>[
          Builder(
            builder: (context) {
              final enabled =
                  onChanged != null && (m != SaleMode.credit || creditEnabled);
              final isSelected = m == selected;
              return Semantics(
                inMutuallyExclusiveGroup: true,
                checked: isSelected,
                enabled: enabled,
                label: saleModeLabel(l10n, m),
                child: Material(
                  color: isSelected ? app.tint(p.primaryContainer) : p.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusCard),
                    side: BorderSide(
                      color: isSelected ? p.primary : p.border,
                      width: isSelected ? app.borderWidth + 1 : app.borderWidth,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('mode-${m.wire}'),
                    onTap: enabled ? () => onChanged!(m) : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: Tokens.sizePrimaryButtonHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(Tokens.space3),
                        child: Row(
                          children: <Widget>[
                            Icon(switch (m) {
                              SaleMode.upiQr => Icons.qr_code_2,
                              SaleMode.card => Icons.credit_card,
                              SaleMode.cash => Icons.payments_outlined,
                              SaleMode.credit => Icons.menu_book_outlined,
                            }, color: enabled ? p.primary : p.textMuted),
                            const SizedBox(width: Tokens.space3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    saleModeLabel(l10n, m),
                                    style: app.text.body.copyWith(
                                      color: enabled ? p.text : p.textMuted,
                                    ),
                                  ),
                                  Text(
                                    switch (m) {
                                      SaleMode.upiQr => l10n.storeModeUpiHint,
                                      SaleMode.card => l10n.storeModeCardHint,
                                      SaleMode.cash => l10n.storeModeCashHint,
                                      SaleMode.credit =>
                                        l10n.storeModeCreditHint,
                                    },
                                    style: app.text.caption.copyWith(
                                      color: enabled
                                          ? p.textSecondary
                                          : p.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected ? p.primary : p.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (m != SaleMode.values.last) const SizedBox(height: Tokens.space2),
        ],
      ],
    );
  }
}

/// Digits and one decimal point for rupee entry.
final List<TextInputFormatter> rupeeInput = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];
