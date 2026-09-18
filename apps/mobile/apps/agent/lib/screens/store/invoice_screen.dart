import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'gst_invoice_view.dart';
import 'store_routes.dart';
import 'store_shell.dart';

/// S04 Invoice / receipt share: invoice number and totals, open the PDF
/// (signed URL, external viewer), send on WhatsApp (server,
/// `POST /v1/invoices/{id}/share`) or share the link via the system sheet.
class InvoiceScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const InvoiceScreen({required this.invoiceId, super.key});

  /// Invoice id.
  final String invoiceId;

  @override
  ConsumerState<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends ConsumerState<InvoiceScreen> {
  bool _busy = false;

  Future<void> _openPdf(Invoice invoice) async {
    final l10n = CoreLocalizations.of(context);
    setState(() => _busy = true);
    final url = await ref.read(storeApiProvider).invoicePdfUrl(invoice.id);
    var opened = false;
    if (url.ok) opened = await ref.read(urlOpenerProvider).open(url.value!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) storeSnack(context, l10n.storePdfFailed);
  }

  Future<void> _whatsApp(Invoice invoice) async {
    final l10n = CoreLocalizations.of(context);
    final buyer = ref.read(posProvider).buyer;
    setState(() => _busy = true);
    final sent = await ref
        .read(storeApiProvider)
        .shareInvoice(
          invoice.id,
          phone: buyer == null ? null : '+91${buyer.phone}',
        );
    if (!mounted) return;
    setState(() => _busy = false);
    storeSnack(
      context,
      sent.ok ? l10n.storeShareSent(sent.value!) : l10n.storeShareFailed,
    );
  }

  Future<void> _shareSheet(Invoice invoice) async {
    final l10n = CoreLocalizations.of(context);
    final url = await ref.read(storeApiProvider).invoicePdfUrl(invoice.id);
    if (!mounted) return;
    if (!url.ok) {
      storeSnack(context, l10n.storeShareFailed);
      return;
    }
    await ref
        .read(textSharerProvider)
        .share(
          l10n.storeShareText(
            invoice.invoiceNo,
            formatInr(invoice.totalPaise),
            url.value!,
          ),
          subject: invoice.invoiceNo,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final value = ref.watch(invoiceProvider(widget.invoiceId));
    final pos = ref.watch(posProvider);
    return StoreShell(
      section: StoreSection.pos,
      title: l10n.storeInvoiceTitle,
      body: StoreResultView<Invoice>(
        value: value,
        onRetry: () => ref.invalidate(invoiceProvider(widget.invoiceId)),
        builder: (invoice) {
          final app = context.app;
          final p = app.palette;
          final change =
              pos.sale?.invoice.id == invoice.id && pos.mode == SaleMode.cash
              ? pos.changePaise
              : null;
          final header = StoreCard(
            key: const Key('invoice-header'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.check_circle, color: p.statusSuccess),
                    const SizedBox(width: Tokens.space2),
                    Expanded(
                      child: Text(
                        l10n.storeInvoicePaid,
                        style: app.text.heading.copyWith(
                          color: p.statusSuccess,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.space3),
                Text(
                  l10n.storeInvoiceNo(invoice.invoiceNo),
                  key: const Key('invoice-number'),
                  style: app.text.title,
                ),
                Text(
                  formatDateTimeIst(invoice.issuedAt),
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: Tokens.space2),
                Text(formatInr(invoice.totalPaise), style: app.text.display),
                if (change != null && change > 0)
                  StoreAmountRow(
                    key: const Key('invoice-change'),
                    label: l10n.storeCashChange,
                    value: formatInr(change),
                    color: p.statusSuccess,
                    strong: true,
                  ),
                const SizedBox(height: Tokens.space3),
                Text(invoice.sellerName, style: app.text.label),
                Text(
                  l10n.storeGstin(invoice.sellerGstin),
                  style: app.text.caption,
                ),
                if (invoice.sellerAddress.isNotEmpty)
                  Text(invoice.sellerAddress, style: app.text.caption),
                const SizedBox(height: Tokens.space2),
                Text(
                  l10n.storeInvoiceBuyer,
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
                Text(invoice.buyerName, style: app.text.label),
              ],
            ),
          );
          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppButton(
                key: const Key('invoice-whatsapp'),
                label: l10n.storeShareWhatsApp,
                icon: Icons.chat_outlined,
                loading: _busy,
                onPressed: () => _whatsApp(invoice),
              ),
              const SizedBox(height: Tokens.space2),
              AppButton(
                key: const Key('invoice-pdf'),
                label: l10n.storeOpenPdf,
                icon: Icons.picture_as_pdf_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: invoice.hasPdf && !_busy
                    ? () => _openPdf(invoice)
                    : null,
              ),
              const SizedBox(height: Tokens.space2),
              AppButton(
                key: const Key('invoice-share'),
                label: l10n.storeShareOther,
                icon: Icons.share_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: () => _shareSheet(invoice),
              ),
              const SizedBox(height: Tokens.space2),
              AppButton(
                key: const Key('invoice-next-sale'),
                label: l10n.storeNextSale,
                icon: Icons.add_shopping_cart,
                variant: AppButtonVariant.tertiary,
                onPressed: () {
                  ref.read(posProvider.notifier).newSale();
                  context.go(StoreRoutes.pos);
                },
              ),
            ],
          );
          final body = StoreCard(
            title: l10n.storeInvoiceTitle,
            child: GstInvoiceView.invoice(invoice),
          );
          return isStoreTwoPane(context)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(
                          Tokens.spaceScreenPadding,
                        ),
                        children: <Widget>[
                          header,
                          const SizedBox(height: Tokens.space4),
                          actions,
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(
                          Tokens.spaceScreenPadding,
                        ),
                        children: <Widget>[body],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                  children: <Widget>[
                    header,
                    const SizedBox(height: Tokens.space4),
                    body,
                    const SizedBox(height: Tokens.space4),
                    actions,
                  ],
                );
        },
      ),
    );
  }
}
