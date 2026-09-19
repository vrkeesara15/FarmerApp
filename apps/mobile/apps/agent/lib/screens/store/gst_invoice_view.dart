import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';

/// GST invoice body: lines with HSN, qty, rate, taxable value, GST rate and
/// amount; CGST + SGST (intra-state) or IGST (inter-state); round-off;
/// total; amount in words when the server issued it (S03 preview, S04).
class GstInvoiceView extends StatelessWidget {
  /// Creates the view.
  const GstInvoiceView({
    required this.lines,
    required this.inter,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.roundOffPaise,
    required this.totalPaise,
    this.amountInWords,
    super.key,
  });

  /// From an invoice preview (the server's, or the local estimate).
  factory GstInvoiceView.preview(GstPreview p, {Key? key}) => GstInvoiceView(
    key: key,
    lines: p.lines,
    inter: p.inter,
    taxablePaise: p.taxablePaise,
    cgstPaise: p.cgstPaise,
    sgstPaise: p.sgstPaise,
    igstPaise: p.igstPaise,
    roundOffPaise: p.roundOffPaise,
    totalPaise: p.totalPaise,
    amountInWords: p.amountInWords,
  );

  /// From the server invoice.
  factory GstInvoiceView.invoice(Invoice i, {Key? key}) => GstInvoiceView(
    key: key,
    lines: i.lines,
    inter: i.inter,
    taxablePaise: i.taxablePaise,
    cgstPaise: i.cgstPaise,
    sgstPaise: i.sgstPaise,
    igstPaise: i.igstPaise,
    roundOffPaise: i.roundOffPaise,
    totalPaise: i.totalPaise,
    amountInWords: i.amountInWords,
  );

  /// Lines.
  final List<InvoiceLine> lines;

  /// IGST.
  final bool inter;

  /// Taxable value.
  final int taxablePaise;

  /// CGST.
  final int cgstPaise;

  /// SGST.
  final int sgstPaise;

  /// IGST.
  final int igstPaise;

  /// Round-off.
  final int roundOffPaise;

  /// Total.
  final int totalPaise;

  /// Words (server).
  final String? amountInWords;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final head = app.text.caption.copyWith(color: p.textSecondary);
    Widget cell(
      String text, {
      TextStyle? style,
      TextAlign? align,
      int flex = 2,
    }) => Expanded(
      flex: flex,
      child: Text(
        text,
        style: style ?? app.text.caption,
        textAlign: align ?? TextAlign.end,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            cell(
              l10n.storeColItem,
              style: head,
              align: TextAlign.start,
              flex: 5,
            ),
            cell(l10n.storeColHsn, style: head, flex: 3),
            cell(l10n.storeColQty, style: head, flex: 1),
            cell(l10n.storeColRate, style: head),
            cell(l10n.storeColGst, style: head),
            cell(l10n.storeColAmount, style: head, flex: 3),
          ],
        ),
        Divider(color: p.border),
        for (final l in lines)
          Padding(
            key: Key('invoice-line-${l.sl}'),
            padding: const EdgeInsets.symmetric(vertical: Tokens.space1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                cell(
                  l.description,
                  style: app.text.caption.copyWith(color: p.text),
                  align: TextAlign.start,
                  flex: 5,
                ),
                cell(l.hsn, flex: 3),
                cell(formatQty(l.qty), flex: 1),
                cell(formatInr(l.unitPricePaise)),
                cell(gstRateLabel(l.gstRateBp)),
                cell(formatInr(l.totalPaise), flex: 3),
              ],
            ),
          ),
        Divider(color: p.border),
        StoreTotalsRow(label: l10n.storeTaxable, paise: taxablePaise),
        if (inter)
          StoreTotalsRow(
            key: const Key('invoice-igst'),
            label: l10n.storeIgst,
            paise: igstPaise,
          )
        else ...<Widget>[
          StoreTotalsRow(
            key: const Key('invoice-cgst'),
            label: l10n.storeCgst,
            paise: cgstPaise,
          ),
          StoreTotalsRow(
            key: const Key('invoice-sgst'),
            label: l10n.storeSgst,
            paise: sgstPaise,
          ),
        ],
        StoreTotalsRow(label: l10n.storeRoundOff, paise: roundOffPaise),
        StoreTotalsRow(
          key: const Key('invoice-total'),
          label: l10n.storeTotal,
          paise: totalPaise,
          strong: true,
        ),
        if (amountInWords != null && amountInWords!.isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          Text(l10n.storeAmountInWords, style: head),
          Text(
            amountInWords!,
            key: const Key('invoice-words'),
            style: app.text.body,
          ),
        ],
      ],
    );
  }
}

/// One totals row.
class StoreTotalsRow extends StatelessWidget {
  /// Creates the row.
  const StoreTotalsRow({
    required this.label,
    required this.paise,
    this.strong = false,
    super.key,
  });

  /// Label.
  final String label;

  /// Amount.
  final int paise;

  /// Bold.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final style = strong ? app.text.heading : app.text.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(formatInr(paise), style: style),
        ],
      ),
    );
  }
}
