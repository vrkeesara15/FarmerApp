import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_shell.dart';

/// Adjustment of a batch to the counted quantity, with a reason (store
/// manager; audited on the server).
Future<void> showAdjustDialog(
  BuildContext context,
  WidgetRef ref,
  StockBatch batch,
) async {
  final l10n = CoreLocalizations.of(context);
  final done = await showDialog<bool>(
    context: context,
    builder: (context) => _AdjustDialog(batch: batch),
  );
  if ((done ?? false) && context.mounted) {
    storeSnack(context, l10n.storeSaved);
    ref.invalidate(stockRowsProvider);
  }
}

class _AdjustDialog extends ConsumerStatefulWidget {
  const _AdjustDialog({required this.batch});

  final StockBatch batch;

  @override
  ConsumerState<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<_AdjustDialog> {
  final TextEditingController _counted = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  bool _tried = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = CoreLocalizations.of(context);
    setState(() => _tried = true);
    final q = double.tryParse(_counted.text);
    if (q == null || q < 0 || _reason.text.trim().isEmpty) return;
    final store = ref.read(activeStoreProvider);
    if (store == null) return;
    setState(() => _busy = true);
    final r = await ref
        .read(storeApiProvider)
        .adjust(
          store.id,
          batch: widget.batch,
          countedQty: q,
          reason: _reason.text.trim(),
        );
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = r.failure!.isOffline
          ? l10n.storeOfflineTitle
          : r.failure!.code == 'negative_stock'
          ? l10n.storeNegativeStock
          : l10n.storeErrorHelp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final q = double.tryParse(_counted.text);
    final qtyBad = _tried && (q == null || q < 0);
    final reasonBad = _tried && _reason.text.trim().isEmpty;
    return AlertDialog(
      key: const Key('adjust-dialog'),
      title: Text(l10n.storeAdjustTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.storeBatch(widget.batch.batchNo)),
          const SizedBox(height: Tokens.space2),
          TextField(
            key: const Key('adjust-qty'),
            controller: _counted,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.storeCountedQty,
              errorText: qtyBad ? l10n.storeQtyRequired : null,
            ),
          ),
          TextField(
            key: const Key('adjust-reason'),
            controller: _reason,
            decoration: InputDecoration(
              labelText: l10n.storeReason,
              hintText: l10n.storeAdjustReasonHint,
              errorText: reasonBad ? l10n.storeReasonRequired : null,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: context.app.palette.statusDanger),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('adjust-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.storeSubmit),
        ),
      ],
    );
  }
}
