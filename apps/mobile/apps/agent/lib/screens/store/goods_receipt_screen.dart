import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_shell.dart';

class _Line {
  StoreItem? item;
  DateTime? expiry;
  final TextEditingController batch = TextEditingController();
  final TextEditingController qty = TextEditingController();
  final TextEditingController cost = TextEditingController();

  void dispose() {
    batch.dispose();
    qty.dispose();
    cost.dispose();
  }
}

/// S07 Goods receipt: lines with SKU (pick or scan), batch number, expiry,
/// quantity and unit cost; submit to `POST /v1/stores/{id}/stock/receipts`;
/// success summary.
class GoodsReceiptScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const GoodsReceiptScreen({super.key});

  @override
  ConsumerState<GoodsReceiptScreen> createState() => _GoodsReceiptScreenState();
}

class _GoodsReceiptScreenState extends ConsumerState<GoodsReceiptScreen> {
  final List<_Line> _lines = <_Line>[_Line()];
  final TextEditingController _reference = TextEditingController();
  bool _tried = false;
  bool _busy = false;
  String? _error;
  StockWriteResult? _done;
  List<ReceiptLine> _submitted = const <ReceiptLine>[];

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _reference.dispose();
    super.dispose();
  }

  Set<LineProblem> _problems(_Line l) => validateReceiptLine(
    item: l.item,
    batchNo: l.batch.text,
    qty: double.tryParse(l.qty.text),
    costPaise: parseRupees(l.cost.text),
    expiry: l.expiry,
    today: ref.read(clockProvider)().toUtc().add(istOffset),
  );

  Future<void> _submit() async {
    final l10n = CoreLocalizations.of(context);
    setState(() {
      _tried = true;
      _error = null;
    });
    if (_lines.any((l) => _problems(l).isNotEmpty)) return;
    final store = ref.read(activeStoreProvider);
    if (store == null) return;
    final lines = <ReceiptLine>[
      for (final l in _lines)
        ReceiptLine(
          item: l.item!,
          batchNo: l.batch.text.trim(),
          expiry: l.expiry,
          qty: double.parse(l.qty.text),
          costPaise: parseRupees(l.cost.text)!,
        ),
    ];
    setState(() => _busy = true);
    final result = await ref
        .read(storeApiProvider)
        .receiveStock(
          store.id,
          lines,
          reference: _reference.text.trim().isEmpty
              ? null
              : _reference.text.trim(),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _done = result.value;
        _submitted = lines;
        ref.invalidate(stockRowsProvider);
      } else {
        _error = result.failure!.isOffline
            ? l10n.storeOfflineTitle
            : result.failure!.code == 'batch_mismatch'
            ? l10n.storeBatchMismatch
            : l10n.storeErrorHelp;
      }
    });
  }

  Future<void> _scanInto(_Line line) async {
    final l10n = CoreLocalizations.of(context);
    final code = await ref.read(barcodeScannerProvider).scan(context);
    final store = ref.read(activeStoreProvider);
    if (code == null || store == null || !mounted) return;
    final found = await ref.read(storeApiProvider).barcode(code, store.id);
    if (!mounted) return;
    if (found.ok) {
      setState(() => line.item = found.value);
    } else {
      storeSnack(context, l10n.storeScanNotFound(code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final role = ref.watch(storeRoleProvider);
    final catalog =
        ref.watch(storeCatalogProvider).value?.value ?? const <StoreItem>[];
    final done = _done;
    return StoreShell(
      section: StoreSection.stock,
      title: l10n.storeReceiptTitle,
      showBack: true,
      body: !role.canMoveStock
          ? EmptyState(
              icon: Icons.lock_outline,
              title: l10n.storeNotAllowedTitle,
              help: l10n.storeReadOnlyBanner,
            )
          : done != null
          ? ListView(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              children: <Widget>[
                StoreCard(
                  key: const Key('receipt-done'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.check_circle,
                        color: app.palette.statusSuccess,
                        size: Tokens.space12,
                      ),
                      Text(l10n.storeReceiptDone, style: app.text.title),
                      Text(
                        l10n.storeReceiptDoneHelp(
                          _submitted.length,
                          formatQty(_submitted.fold(0, (a, l) => a + l.qty)),
                        ),
                        style: app.text.body,
                      ),
                      const SizedBox(height: Tokens.space2),
                      for (final l in _submitted)
                        StoreAmountRow(
                          label:
                              '${l.item.name} ${l.item.packLabel} · ${l10n.storeBatch(l.batchNo)}',
                          value: formatQty(l.qty),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.space4),
                AppButton(
                  key: const Key('receipt-another'),
                  label: l10n.storeActionReceive,
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => setState(() {
                    for (final l in _lines) {
                      l.dispose();
                    }
                    _lines
                      ..clear()
                      ..add(_Line());
                    _reference.clear();
                    _tried = false;
                    _done = null;
                  }),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              children: <Widget>[
                AppTextField(
                  key: const Key('receipt-reference'),
                  label: l10n.storeReference,
                  controller: _reference,
                ),
                const SizedBox(height: Tokens.space4),
                for (var i = 0; i < _lines.length; i++) ...<Widget>[
                  _lineCard(context, i, catalog),
                  const SizedBox(height: Tokens.space3),
                ],
                AppButton(
                  key: const Key('receipt-add-line'),
                  label: l10n.storeAddLine,
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => setState(() => _lines.add(_Line())),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: Tokens.space3),
                  Text(
                    _error!,
                    key: const Key('receipt-error'),
                    style: app.text.body.copyWith(
                      color: app.palette.statusDanger,
                    ),
                  ),
                ],
                const SizedBox(height: Tokens.space4),
                AppButton(
                  key: const Key('receipt-submit'),
                  label: l10n.storeReceiptSubmit,
                  icon: Icons.move_to_inbox_outlined,
                  loading: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
    );
  }

  Widget _lineCard(BuildContext context, int i, List<StoreItem> catalog) {
    final l10n = CoreLocalizations.of(context);
    final line = _lines[i];
    final problems = _tried ? _problems(line) : const <LineProblem>{};
    final twoCol = isStoreTwoPane(context);
    Widget field(Widget a, Widget b) => twoCol
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: a),
              const SizedBox(width: Tokens.space3),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              a,
              const SizedBox(height: Tokens.space2),
              b,
            ],
          );
    return StoreCard(
      key: Key('receipt-line-$i'),
      title: '${l10n.storeSku} ${i + 1}',
      trailing: _lines.length > 1
          ? IconButton(
              tooltip: l10n.storeRemoveLine,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _lines.removeAt(i).dispose()),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: Key('receipt-sku-$i'),
                  initialValue: line.item?.skuId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.storeFindSku,
                    errorText: problems.contains(LineProblem.missing)
                        ? l10n.storeSkuRequired
                        : null,
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final c in catalog)
                      DropdownMenuItem<String>(
                        value: c.skuId,
                        child: Text(
                          '${c.name} ${c.packLabel}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(
                    () => line.item = catalog.firstWhere((c) => c.skuId == id),
                  ),
                ),
              ),
              IconButton(
                key: Key('receipt-scan-$i'),
                tooltip: l10n.storeScan,
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () => _scanInto(line),
              ),
            ],
          ),
          const SizedBox(height: Tokens.space2),
          field(
            TextField(
              key: Key('receipt-batch-$i'),
              controller: line.batch,
              decoration: InputDecoration(
                labelText: l10n.storeBatchNo,
                errorText: problems.contains(LineProblem.batchNo)
                    ? l10n.storeBatchNoRequired
                    : null,
              ),
            ),
            InkWell(
              key: Key('receipt-expiry-$i'),
              onTap: () async {
                final now = ref.read(clockProvider)();
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      line.expiry ?? now.add(const Duration(days: 365)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365 * 6)),
                );
                if (picked != null) setState(() => line.expiry = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.storeExpiryDate,
                  errorText: problems.contains(LineProblem.expiry)
                      ? l10n.storeExpiryPast
                      : null,
                  suffixIcon: const Icon(Icons.event_outlined),
                ),
                child: Text(
                  line.expiry == null
                      ? l10n.storeNoExpiry
                      : formatDateIst(line.expiry!),
                ),
              ),
            ),
          ),
          const SizedBox(height: Tokens.space2),
          field(
            TextField(
              key: Key('receipt-qty-$i'),
              controller: line.qty,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.storeQuantity,
                errorText: problems.contains(LineProblem.qty)
                    ? l10n.storeQtyRequired
                    : null,
              ),
            ),
            TextField(
              key: Key('receipt-cost-$i'),
              controller: line.cost,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.storeUnitCost,
                errorText: problems.contains(LineProblem.cost)
                    ? l10n.storeCostRequired
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
