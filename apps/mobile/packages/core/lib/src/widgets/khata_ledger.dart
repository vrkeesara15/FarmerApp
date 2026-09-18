import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../utils/format.dart';
import 'app_button.dart';

/// One khata entry.
@immutable
class KhataEntry {
  /// Creates the entry.
  const KhataEntry({
    required this.dateUtc,
    required this.description,
    required this.amountPaise,
    required this.isCredit,
  });

  /// Entry time in UTC.
  final DateTime dateUtc;

  /// Localised description, e.g. product or "Cash received".
  final String description;

  /// Amount in paise (always positive).
  final int amountPaise;

  /// Credit (payment received) or debit (sale on credit).
  final bool isCredit;
}

/// Farmer khata: balance header, due date and debit/credit entries
/// (SPEC 13.1 `KhataLedger`).
class KhataLedger extends StatelessWidget {
  /// Creates the ledger.
  const KhataLedger({
    required this.balancePaise,
    this.dueDateUtc,
    this.entries = const <KhataEntry>[],
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Outstanding balance in paise (positive = farmer owes).
  final int balancePaise;

  /// Due date in UTC.
  final DateTime? dueDateUtc;

  /// Entries, newest first.
  final List<KhataEntry> entries;

  /// Label of the primary action ("Pay now" for farmers, "Collect" for agents).
  final String? actionLabel;

  /// Primary action handler; the button is hidden when `null`.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final overdue =
        dueDateUtc != null && dueDateUtc!.isBefore(DateTime.now().toUtc());
    final balanceColor = balancePaise > 0
        ? (overdue ? p.statusDanger : p.statusWarning)
        : p.statusSuccess;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(Tokens.space4),
            decoration: BoxDecoration(
              color: app.tint(p.background),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Tokens.radiusCard),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.khataBalance,
                  style: app.text.label.copyWith(color: p.textSecondary),
                ),
                Text(
                  formatInr(balancePaise),
                  style: app.text.display.copyWith(color: balanceColor),
                ),
                if (dueDateUtc != null) ...<Widget>[
                  const SizedBox(height: Tokens.space1),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.event_outlined,
                        size: Tokens.space4,
                        color: balanceColor,
                      ),
                      const SizedBox(width: Tokens.space1),
                      Expanded(
                        child: Text(
                          l10n.khataDueDate(formatDateIst(dueDateUtc!)),
                          style: app.text.body.copyWith(color: balanceColor),
                        ),
                      ),
                    ],
                  ),
                ],
                if (onAction != null) ...<Widget>[
                  const SizedBox(height: Tokens.space3),
                  AppButton(
                    label: actionLabel ?? l10n.khataPayNow,
                    icon: Icons.currency_rupee,
                    onPressed: onAction,
                  ),
                ],
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Tokens.space4),
              child: Text(
                l10n.khataNoEntries,
                style: app.text.body.copyWith(color: p.textSecondary),
              ),
            )
          else
            for (var i = 0; i < entries.length; i++) ...<Widget>[
              Divider(height: app.borderWidth, color: p.border),
              _EntryRow(entry: entries[i]),
            ],
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final KhataEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final color = entry.isCredit ? p.statusSuccess : p.text;
    final sign = entry.isCredit ? '-' : '+';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space4,
        vertical: Tokens.space3,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            entry.isCredit
                ? Icons.arrow_circle_down_outlined
                : Icons.arrow_circle_up_outlined,
            color: color,
          ),
          const SizedBox(width: Tokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.description,
                  style: app.text.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${formatDateIst(entry.dateUtc)} · '
                  '${entry.isCredit ? l10n.khataCredit : l10n.khataDebit}',
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.space2),
          Text(
            '$sign${formatInr(entry.amountPaise)}',
            style: app.text.heading.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
