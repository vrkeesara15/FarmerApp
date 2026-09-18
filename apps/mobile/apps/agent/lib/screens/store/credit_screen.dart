import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_shell.dart';

/// S09 Credit (ST-007): cluster heads approve or reject pending credit
/// sales beyond a farmer's limit (with a note); store managers set a
/// farmer's limit up to the manager cap (₹50,000 by default; above it the
/// server answers `credit_limit_needs_cluster_head`) and see the pending
/// requests of their store.
class CreditScreen extends ConsumerWidget {
  /// Creates the screen.
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final role = ref.watch(storeRoleProvider);
    final approvals = ref.watch(creditApprovalsProvider);
    final list = StoreResultView<List<CreditApproval>>(
      value: approvals,
      onRetry: () => ref.invalidate(creditApprovalsProvider),
      builder: (items) => items.isEmpty
          ? EmptyState(
              key: const Key('credit-empty'),
              icon: Icons.task_alt,
              title: l10n.storeApprovalsEmpty,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: Tokens.space3),
              itemBuilder: (context, i) => _ApprovalCard(
                approval: items[i],
                canDecide: role.canApproveCredit,
              ),
            ),
    );
    final twoPane = isStoreTwoPane(context);
    return StoreShell(
      section: StoreSection.credit,
      title: l10n.storeCreditTitle,
      body: !role.canSetCreditLimit
          ? list
          : twoPane
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(Tokens.spaceScreenPadding),
                    child: _LimitForm(),
                  ),
                ),
                VerticalDivider(width: 1, color: context.app.palette.border),
                Expanded(child: list),
              ],
            )
          : Column(
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(Tokens.spaceScreenPadding),
                  child: _LimitForm(),
                ),
                Expanded(child: list),
              ],
            ),
    );
  }
}

class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({required this.approval, required this.canDecide});

  final CreditApproval approval;
  final bool canDecide;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final l10n = CoreLocalizations.of(context);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(approve: approve),
    );
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(storeApiProvider)
        .decideCredit(
          widget.approval.id,
          approve: approve,
          note: note.isEmpty ? null : note,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    storeSnack(
      context,
      result.ok
          ? (approve ? l10n.storeApproved : l10n.storeRejected)
          : result.failure!.isOffline
          ? l10n.storeOfflineTitle
          : result.failure!.code == 'approval_not_pending'
          ? l10n.storeApprovalGone
          : l10n.storeErrorHelp,
    );
    ref.invalidate(creditApprovalsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final a = widget.approval;
    final names = ref.watch(storeFarmerNamesProvider).value ?? const {};
    final stores =
        ref.watch(storesProvider).value?.value ?? const <StoreBrief>[];
    final store = stores.where((s) => s.id == a.storeId).firstOrNull;
    final farmer =
        names[a.farmerId] ??
        l10n.storeFarmerUnknown(
          a.farmerId.length <= 6
              ? a.farmerId
              : a.farmerId.substring(a.farmerId.length - 6).toUpperCase(),
        );
    return StoreCard(
      key: Key('approval-${a.id}'),
      title: farmer,
      trailing: store == null
          ? null
          : StoreChip(label: store.name, color: p.statusInfo),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StoreAmountRow(
            label: l10n.storeApprovalAmount,
            value: formatInr(a.amountPaise),
            strong: true,
          ),
          StoreAmountRow(
            label: l10n.storeCreditBalance,
            value: formatInr(a.balancePaise),
          ),
          StoreAmountRow(
            label: l10n.storeCreditLimit,
            value: formatInr(a.limitPaise),
          ),
          StoreAmountRow(
            label: l10n.storeShortfall,
            value: formatInr(a.shortfallPaise),
            color: p.statusDanger,
          ),
          if (a.createdAt != null)
            Text(
              formatDateTimeIst(a.createdAt!),
              style: app.text.caption.copyWith(color: p.textSecondary),
            ),
          if (widget.canDecide) ...<Widget>[
            const SizedBox(height: Tokens.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    key: Key('approval-reject-${a.id}'),
                    label: l10n.storeReject,
                    icon: Icons.close,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.medium,
                    onPressed: _busy ? null : () => _decide(false),
                  ),
                ),
                const SizedBox(width: Tokens.space3),
                Expanded(
                  child: AppButton(
                    key: Key('approval-approve-${a.id}'),
                    label: l10n.storeApprove,
                    icon: Icons.check,
                    size: AppButtonSize.medium,
                    loading: _busy,
                    onPressed: () => _decide(true),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.approve});

  final bool approve;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.approve ? l10n.storeApprove : l10n.storeReject),
      content: TextField(
        key: const Key('approval-note'),
        controller: _note,
        decoration: InputDecoration(labelText: l10n.storeDecisionNote),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('approval-confirm'),
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: Text(widget.approve ? l10n.storeApprove : l10n.storeReject),
        ),
      ],
    );
  }
}

class _LimitForm extends ConsumerStatefulWidget {
  const _LimitForm();

  @override
  ConsumerState<_LimitForm> createState() => _LimitFormState();
}

class _LimitFormState extends ConsumerState<_LimitForm> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  String? _farmerId;
  String? _farmerName;
  String? _message;
  bool _error = false;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final l10n = CoreLocalizations.of(context);
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final farmer = await ref
        .read(farmerRepositoryProvider)
        .findByPhone('+91$digits');
    if (!mounted) return;
    setState(() {
      _farmerId = farmer?.id;
      _farmerName = farmer?.name;
      _error = farmer == null;
      _message = farmer == null ? l10n.storeLimitFarmerNotFound : null;
    });
  }

  Future<void> _save() async {
    final l10n = CoreLocalizations.of(context);
    final paise = parseRupees(_amount.text);
    final store = ref.read(activeStoreProvider);
    if (_farmerId == null || paise == null || store == null) {
      setState(() {
        _error = true;
        _message = _farmerId == null
            ? l10n.storeLimitFarmerNotFound
            : l10n.storeLimitAmountRequired;
      });
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(storeApiProvider)
        .setCreditLimit(_farmerId!, storeId: store.id, limitPaise: paise);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = !result.ok;
      _message = result.ok
          ? l10n.storeLimitSaved(formatInr(result.value!, showPaise: false))
          : result.failure!.code == 'credit_limit_needs_cluster_head'
          ? l10n.storeLimitNeedsClusterHead(
              formatInr(storeManagerCreditCapPaise, showPaise: false),
            )
          : result.failure!.isOffline
          ? l10n.storeOfflineTitle
          : l10n.storeErrorHelp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final paise = parseRupees(_amount.text);
    final overCap = paise != null && paise > storeManagerCreditCapPaise;
    return StoreCard(
      key: const Key('credit-limit-form'),
      title: l10n.storeSetLimitTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('credit-phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    counterText: '',
                    prefixText: '${l10n.phonePrefix} ',
                    labelText: l10n.storeBuyerPhone,
                  ),
                  onSubmitted: (_) => _find(),
                ),
              ),
              const SizedBox(width: Tokens.space2),
              AppButton(
                key: const Key('credit-find'),
                label: l10n.storeBuyerFind,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                expand: false,
                onPressed: _find,
              ),
            ],
          ),
          if (_farmerName != null) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            Text(
              _farmerName!,
              key: const Key('credit-farmer'),
              style: app.text.label,
            ),
          ],
          const SizedBox(height: Tokens.space2),
          TextField(
            key: const Key('credit-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.storeLimitAmount,
              prefixIcon: const Icon(Icons.currency_rupee),
              helperText: l10n.storeManagerCapHint(
                formatInr(storeManagerCreditCapPaise, showPaise: false),
              ),
              helperMaxLines: 2,
            ),
          ),
          if (overCap) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            Text(
              l10n.storeLimitNeedsClusterHead(
                formatInr(storeManagerCreditCapPaise, showPaise: false),
              ),
              key: const Key('credit-over-cap'),
              style: app.text.caption.copyWith(color: p.statusWarning),
            ),
          ],
          if (_message != null) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            Text(
              _message!,
              key: const Key('credit-message'),
              style: app.text.body.copyWith(
                color: _error ? p.statusDanger : p.statusSuccess,
              ),
            ),
          ],
          const SizedBox(height: Tokens.space3),
          AppButton(
            key: const Key('credit-save'),
            label: l10n.storeSetLimit,
            icon: Icons.save_outlined,
            loading: _busy,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
