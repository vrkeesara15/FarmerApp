import 'dart:async';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'field_widgets.dart';

/// A61 Travel allowance (FA-023): km by day for the month, the allowance
/// they add up to, the expense claims and their status, and "add expense"
/// with a receipt photo through the NF-004 pipeline.
///
/// The statement is cached (`GET /v1/travel/statement`), so the screen
/// opens offline; a new claim is queued in the outbox with its receipt as a
/// resumable upload and shows as "Waiting to sync" until the op is applied.
class TravelScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const TravelScreen({super.key});

  @override
  ConsumerState<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends ConsumerState<TravelScreen> {
  @override
  void initState() {
    super.initState();
    final month = istMonthKey(ref.read(clockProvider)());
    unawaited(ref.read(fieldRepositoryProvider).refreshTravel(month));
  }

  Future<void> _addClaim() async {
    final result = await showModalBottomSheet<AddClaimResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const AddExpenseSheet(),
    );
    if (result == null || !mounted) return;
    final path = await ref
        .read(photoStoreProvider)
        .save(
          'receipt-${result.claimDate}-${result.amountPaise}.jpg',
          result.receipt,
        );
    await ref
        .read(fieldRepositoryProvider)
        .addClaim(
          claimDate: result.claimDate,
          type: result.type,
          amountPaise: result.amountPaise,
          receiptPath: path,
          receiptBytes: result.receipt,
          note: result.note,
        );
    if (!mounted) return;
    final l10n = CoreLocalizations.of(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.travelClaimQueued)));
  }

  String _typeLabel(CoreLocalizations l10n, ClaimType t) => switch (t) {
    ClaimType.fuel => l10n.travelClaimTypeFuel,
    ClaimType.bus => l10n.travelClaimTypeBus,
    ClaimType.other => l10n.travelClaimTypeOther,
  };

  String _statusLabel(CoreLocalizations l10n, ClaimStatus s) => switch (s) {
    ClaimStatus.queued => l10n.travelClaimStatusQueued,
    ClaimStatus.submitted => l10n.travelClaimStatusSubmitted,
    ClaimStatus.approved => l10n.travelClaimStatusApproved,
    ClaimStatus.rejected => l10n.travelClaimStatusRejected,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final month = istMonthKey(ref.watch(clockProvider)());
    final cached = ref.watch(travelStatementProvider(month));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.travelTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('travel-add-claim'),
        onPressed: () => unawaited(_addClaim()),
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text(l10n.travelAddClaim),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: cached.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorState(
                  onRetry: () => ref.invalidate(travelStatementProvider(month)),
                ),
                data: (view) {
                  final s = view.value;
                  if (s == null || s.isEmpty) {
                    return EmptyState(
                      key: const Key('travel-empty'),
                      icon: Icons.directions_bike_outlined,
                      title: l10n.travelEmpty,
                      help: l10n.travelEmptyHelp,
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Tokens.spaceScreenPadding,
                      Tokens.spaceScreenPadding,
                      Tokens.spaceScreenPadding,
                      Tokens.space12 * 2,
                    ),
                    children: <Widget>[
                      if (view.asOf != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FieldCaption(
                            l10n.fieldAsOf(formatDateTimeIst(view.asOf!)),
                            icon: Icons.schedule,
                          ),
                        ),
                      const SizedBox(height: Tokens.space2),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: StatTile(
                              key: const Key('travel-km-total'),
                              value: s.kmCappedTotal.toStringAsFixed(1),
                              label: l10n.travelKmByDay,
                              icon: Icons.route_outlined,
                            ),
                          ),
                          const SizedBox(width: Tokens.space2),
                          Expanded(
                            child: StatTile(
                              key: const Key('travel-ta-total'),
                              value: formatInr(
                                s.taTotalPaise,
                                showPaise: false,
                              ),
                              label: l10n.travelTaTotal,
                              icon: Icons.currency_rupee,
                            ),
                          ),
                          const SizedBox(width: Tokens.space2),
                          Expanded(
                            child: StatTile(
                              key: const Key('travel-payable'),
                              value: formatInr(
                                s.payablePaise,
                                showPaise: false,
                              ),
                              label: l10n.travelPayable,
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Tokens.space4),
                      Text(l10n.travelKmByDay, style: app.text.heading),
                      const SizedBox(height: Tokens.space2),
                      for (final d in s.days)
                        FieldCard(
                          key: Key('travel-day-${d.date}'),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              formatDateIst(
                                DateTime.parse('${d.date}T00:00:00Z'),
                              ),
                              style: app.text.label,
                            ),
                            subtitle: d.capped
                                ? FieldCaption(
                                    l10n.travelCapped(d.capKm),
                                    icon: Icons.warning_amber_outlined,
                                    color: p.statusWarning,
                                  )
                                : null,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                Text(
                                  l10n.travelDayKm(
                                    d.kmCapped.toStringAsFixed(1),
                                  ),
                                  style: app.text.body,
                                ),
                                Text(
                                  formatInr(d.taPaise, showPaise: false),
                                  style: app.text.caption.copyWith(
                                    color: p.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: Tokens.space4),
                      Text(l10n.travelClaimsTitle, style: app.text.heading),
                      const SizedBox(height: Tokens.space2),
                      if (s.claims.isEmpty)
                        FieldCard(
                          child: EmptyState(
                            key: const Key('travel-claims-empty'),
                            icon: Icons.receipt_long_outlined,
                            title: l10n.travelClaimsTitle,
                            help: l10n.travelEmptyHelp,
                          ),
                        )
                      else
                        for (final c in s.claims)
                          FieldCard(
                            key: Key('travel-claim-${c.id}'),
                            child: ListTile(
                              leading: Icon(
                                Icons.receipt_long_outlined,
                                color: switch (c.status) {
                                  ClaimStatus.approved => p.statusSuccess,
                                  ClaimStatus.rejected => p.statusDanger,
                                  _ => p.textSecondary,
                                },
                              ),
                              title: Text(
                                '${_typeLabel(l10n, c.type)} · '
                                '${formatInr(c.amountPaise)}',
                                style: app.text.label,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  FieldCaption(_statusLabel(l10n, c.status)),
                                  if (c.note != null && c.note!.isNotEmpty)
                                    Text(c.note!, style: app.text.body),
                                  if (c.decisionNote != null)
                                    Text(
                                      c.decisionNote!,
                                      style: app.text.caption,
                                    ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the A61 "add expense" sheet hands back.
class AddClaimResult {
  /// Creates the result.
  const AddClaimResult({
    required this.claimDate,
    required this.type,
    required this.amountPaise,
    required this.receipt,
    this.note,
  });

  /// `YYYY-MM-DD` the expense was incurred.
  final String claimDate;

  /// Fuel, bus or other.
  final ClaimType type;

  /// Amount in paise.
  final int amountPaise;

  /// Processed receipt JPEG (NF-004).
  final Uint8List receipt;

  /// Officer's note.
  final String? note;
}

/// A61 "add expense": type, amount, receipt photo and a note with FA-005
/// voice input. Everything is queued offline.
class AddExpenseSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const AddExpenseSheet({super.key});

  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  ClaimType _type = ClaimType.fuel;
  Uint8List? _receipt;
  bool _busy = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _amountPaise {
    final rupees = double.tryParse(_amount.text.trim());
    return rupees == null ? 0 : (rupees * 100).round();
  }

  Future<void> _capture() async {
    setState(() => _busy = true);
    final pending = await ref.read(receiptCaptureProvider)();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (pending != null) _receipt = pending.bytes;
    });
  }

  void _save() {
    if (_amountPaise <= 0 || _receipt == null) {
      setState(() => _showErrors = true);
      return;
    }
    Navigator.of(context).pop(
      AddClaimResult(
        claimDate: istDateKey(ref.read(clockProvider)()),
        type: _type,
        amountPaise: _amountPaise,
        receipt: _receipt!,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    String typeLabel(ClaimType t) => switch (t) {
      ClaimType.fuel => l10n.travelClaimTypeFuel,
      ClaimType.bus => l10n.travelClaimTypeBus,
      ClaimType.other => l10n.travelClaimTypeOther,
    };
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.spaceScreenPadding,
        right: Tokens.spaceScreenPadding,
        top: Tokens.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.travelAddClaim, style: app.text.heading),
            const SizedBox(height: Tokens.space3),
            Text(
              l10n.travelClaimType,
              style: app.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: Tokens.space2),
            Wrap(
              spacing: Tokens.space2,
              children: <Widget>[
                for (final t in ClaimType.values)
                  ChoiceChip(
                    key: Key('claim-type-${t.name}'),
                    label: Text(typeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space3),
            AppTextField(
              key: const Key('claim-amount'),
              label: l10n.travelClaimAmount,
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              errorText: _showErrors && _amountPaise <= 0
                  ? l10n.travelClaimAmountRequired
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Tokens.space3),
            AppButton(
              key: const Key('claim-take-photo'),
              label: _receipt == null
                  ? l10n.travelClaimTakePhoto
                  : l10n.travelClaimReceipt,
              icon: Icons.photo_camera_outlined,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              loading: _busy,
              onPressed: () => unawaited(_capture()),
            ),
            if (_receipt != null)
              Padding(
                padding: const EdgeInsets.only(top: Tokens.space2),
                child: FieldCaption(
                  l10n.travelClaimReceipt,
                  key: const Key('claim-receipt-ready'),
                  icon: Icons.check_circle_outline,
                  color: p.statusSuccess,
                ),
              ),
            if (_showErrors && _receipt == null)
              Padding(
                padding: const EdgeInsets.only(top: Tokens.space2),
                child: FieldCaption(
                  l10n.travelClaimReceiptRequired,
                  key: const Key('claim-receipt-missing'),
                  icon: Icons.error_outline,
                  color: p.statusDanger,
                ),
              ),
            const SizedBox(height: Tokens.space3),
            VoiceTextField(
              label: l10n.travelClaimNote,
              controller: _note,
              maxLines: 2,
              fieldKey: const Key('claim-note'),
              micKey: const Key('claim-note-mic'),
            ),
            const SizedBox(height: Tokens.space4),
            AppButton(
              key: const Key('claim-save'),
              label: l10n.actionDone,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
