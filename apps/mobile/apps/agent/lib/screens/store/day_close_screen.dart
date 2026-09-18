import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_shell.dart';

/// S10 Day close (ST-006): expected cash from the day summary, cash count
/// with a denomination helper (₹500 / 200 / 100 / 50 / 20 / 10 notes and
/// coins), live variance with the threshold warning, deposit slip photo
/// (in-app camera, NF-004, resumable upload), notes, submit; the closed
/// state with its summary; a repeat close is refused by the server (409).
class DayCloseScreen extends ConsumerWidget {
  /// Creates the screen.
  const DayCloseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final role = ref.watch(storeRoleProvider);
    final summary = ref.watch(daySummaryProvider);
    final state = ref.watch(dayCloseProvider);
    return StoreShell(
      section: StoreSection.dayClose,
      title: l10n.storeDayCloseTitle,
      body: StoreResultView<DaySummary>(
        value: summary,
        onRetry: () => ref.invalidate(daySummaryProvider),
        builder: (s) {
          final close = state.result ?? s.dayClose;
          if (close != null && close.isClosed) {
            return ListView(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              children: <Widget>[
                if (state.phase == DayClosePhase.alreadyClosed) ...<Widget>[
                  Text(
                    l10n.storeDayAlreadyClosed,
                    key: const Key('dayclose-already'),
                    style: context.app.text.body.copyWith(
                      color: context.app.palette.statusWarning,
                    ),
                  ),
                  const SizedBox(height: Tokens.space3),
                ],
                _ClosedSummary(close: close),
              ],
            );
          }
          if (!role.canCloseDay) {
            return ListView(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              children: <Widget>[
                StoreCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      StoreChip(
                        label: l10n.storeDayOpen,
                        color: context.app.palette.statusWarning,
                      ),
                      const SizedBox(height: Tokens.space3),
                      StoreAmountRow(
                        label: l10n.storeExpectedCash,
                        value: formatInr(s.expectedCashPaise),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          const count = _CountCard();
          final result = _ResultCard(summary: s);
          if (isStoreTwoPane(context)) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(Tokens.spaceScreenPadding),
                    child: count,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    child: result,
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
            children: <Widget>[
              count,
              const SizedBox(height: Tokens.space4),
              result,
            ],
          );
        },
      ),
    );
  }
}

class _CountCard extends ConsumerWidget {
  const _CountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(dayCloseProvider);
    final notifier = ref.read(dayCloseProvider.notifier);
    return StoreCard(
      key: const Key('dayclose-count'),
      title: l10n.storeCashCount,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final d in noteDenominationsPaise)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Tokens.space1),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      formatInr(d, showPaise: false),
                      style: app.text.heading,
                    ),
                  ),
                  Text('×', style: app.text.body),
                  const SizedBox(width: Tokens.space2),
                  SizedBox(
                    width: 88,
                    child: _CountField(
                      key: Key('dayclose-note-$d'),
                      initial: state.counts[d],
                      onChanged: (v) => notifier.setCount(d, v),
                    ),
                  ),
                  const SizedBox(width: Tokens.space2),
                  Expanded(
                    child: Text(
                      formatInr(d * (state.counts[d] ?? 0), showPaise: false),
                      textAlign: TextAlign.end,
                      style: app.text.body,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Tokens.space2),
          Row(
            children: <Widget>[
              Expanded(child: Text(l10n.storeCoins, style: app.text.heading)),
              SizedBox(
                width: 140,
                child: TextFormField(
                  key: const Key('dayclose-coins'),
                  initialValue: state.coinsPaise == 0
                      ? ''
                      : (state.coinsPaise ~/ 100).toString(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                  onChanged: (v) => notifier.setCoins(parseRupees(v) ?? 0),
                ),
              ),
            ],
          ),
          const Divider(),
          StoreAmountRow(
            key: const Key('dayclose-counted'),
            label: l10n.storeCountedCash,
            value: formatInr(state.countedPaise),
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _CountField extends StatelessWidget {
  const _CountField({
    required this.initial,
    required this.onChanged,
    super.key,
  });

  final int? initial;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initial == null || initial == 0 ? '' : '$initial',
    keyboardType: TextInputType.number,
    textAlign: TextAlign.end,
    inputFormatters: <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
    ],
    onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
  );
}

class _ResultCard extends ConsumerStatefulWidget {
  const _ResultCard({required this.summary});

  final DaySummary summary;

  @override
  ConsumerState<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends ConsumerState<_ResultCard> {
  final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notes.text = ref.read(dayCloseProvider).notes;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(dayCloseProvider);
    final notifier = ref.read(dayCloseProvider.notifier);
    final expected = widget.summary.expectedCashPaise;
    final variance = cashVariance(
      countedPaise: state.countedPaise,
      expectedPaise: expected,
    );
    final over = varianceOverThreshold(variance);
    return StoreCard(
      key: const Key('dayclose-result'),
      title: l10n.storeDayCloseTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StoreAmountRow(
            key: const Key('dayclose-expected'),
            label: l10n.storeExpectedCash,
            value: formatInr(expected),
          ),
          StoreAmountRow(
            label: l10n.storeCountedCash,
            value: formatInr(state.countedPaise),
          ),
          StoreAmountRow(
            key: const Key('dayclose-variance'),
            label: l10n.storeVariance,
            value: formatInr(variance),
            strong: true,
            color: variance == 0
                ? p.statusSuccess
                : over
                ? p.statusDanger
                : p.statusWarning,
          ),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.space1),
              child: Row(
                key: const Key('dayclose-over-threshold'),
                children: <Widget>[
                  Icon(Icons.warning_amber_outlined, color: p.statusDanger),
                  const SizedBox(width: Tokens.space2),
                  Expanded(
                    child: Text(
                      l10n.storeVarianceOver(
                        formatInr(
                          defaultVarianceThresholdPaise,
                          showPaise: false,
                        ),
                      ),
                      style: app.text.caption.copyWith(color: p.statusDanger),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Tokens.space4),
          Text(l10n.storeDepositSlip, style: app.text.label),
          const SizedBox(height: Tokens.space2),
          Row(
            children: <Widget>[
              Container(
                width: 96,
                height: 72,
                decoration: BoxDecoration(
                  color: app.tint(p.background),
                  borderRadius: BorderRadius.circular(Tokens.radiusInput),
                  border: Border.fromBorderSide(app.borderSide),
                ),
                clipBehavior: Clip.antiAlias,
                child: state.slip == null
                    ? Icon(Icons.receipt_long_outlined, color: p.textMuted)
                    : Image.memory(
                        state.slip!,
                        key: const Key('dayclose-slip-thumb'),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.check_circle, color: p.statusSuccess),
                      ),
              ),
              const SizedBox(width: Tokens.space3),
              Expanded(
                child: AppButton(
                  key: const Key('dayclose-photo'),
                  label: state.slip == null
                      ? l10n.storeTakePhoto
                      : l10n.storeRetakePhoto,
                  icon: Icons.photo_camera_outlined,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  onPressed: state.phase == DayClosePhase.submitting
                      ? null
                      : notifier.captureSlip,
                ),
              ),
            ],
          ),
          if (state.phase == DayClosePhase.slipRequired)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.space1),
              child: Text(
                l10n.storeSlipRequired,
                key: const Key('dayclose-slip-required'),
                style: app.text.caption.copyWith(color: p.statusDanger),
              ),
            ),
          const SizedBox(height: Tokens.space3),
          TextField(
            key: const Key('dayclose-notes'),
            controller: _notes,
            maxLines: 2,
            onChanged: notifier.setNotes,
            decoration: InputDecoration(labelText: l10n.storeCloseNotes),
          ),
          if (state.phase == DayClosePhase.offline ||
              state.phase == DayClosePhase.failed) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            Text(
              state.phase == DayClosePhase.offline
                  ? l10n.storeOfflineHelp
                  : l10n.storeErrorHelp,
              key: const Key('dayclose-error'),
              style: app.text.body.copyWith(color: p.statusDanger),
            ),
          ],
          const SizedBox(height: Tokens.space4),
          AppButton(
            key: const Key('dayclose-submit'),
            label: l10n.storeCloseDay,
            icon: Icons.lock_outline,
            loading: state.phase == DayClosePhase.submitting,
            onPressed: notifier.submit,
          ),
        ],
      ),
    );
  }
}

class _ClosedSummary extends StatelessWidget {
  const _ClosedSummary({required this.close});

  final DayClose close;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return StoreCard(
      key: const Key('dayclose-closed'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.lock_outline, color: p.statusSuccess),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Text(
                  l10n.storeDayClosedTitle,
                  style: app.text.title.copyWith(color: p.statusSuccess),
                ),
              ),
              if (close.flagged)
                StoreChip(
                  key: const Key('dayclose-flagged'),
                  label: l10n.storeFlagged,
                  color: p.statusDanger,
                  icon: Icons.flag_outlined,
                ),
            ],
          ),
          if (close.closedAt != null)
            Text(
              l10n.storeDayClosed(formatTimeIst(close.closedAt!)),
              style: app.text.caption.copyWith(color: p.textSecondary),
            ),
          const SizedBox(height: Tokens.space3),
          StoreAmountRow(
            label: l10n.storeExpectedCash,
            value: formatInr(close.expectedPaise),
          ),
          StoreAmountRow(
            label: l10n.storeCountedCash,
            value: formatInr(close.countedPaise),
          ),
          StoreAmountRow(
            key: const Key('dayclose-closed-variance'),
            label: l10n.storeVariance,
            value: formatInr(close.variancePaise),
            strong: true,
            color: close.flagged ? p.statusDanger : null,
          ),
          if (close.notes != null && close.notes!.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            Text(close.notes!, style: app.text.body),
          ],
        ],
      ),
    );
  }
}
