import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_shell.dart';

class _Line {
  String? skuId;
  StockBatch? batch;
  final TextEditingController qty = TextEditingController();
}

/// S08 Stock transfer: destination store from
/// `GET /v1/stock/transfer-destinations` (the cluster's other stores,
/// nearest first, with the distance), lines with batch selection (FEFO
/// suggested: earliest unexpired batch first), qty <= available; submit to
/// `POST /v1/stock/transfers`. The 403s `transfer_source_not_allowed` /
/// `transfer_destination_not_allowed` are explained.
class StockTransferScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const StockTransferScreen({super.key});

  @override
  ConsumerState<StockTransferScreen> createState() =>
      _StockTransferScreenState();
}

class _StockTransferScreenState extends ConsumerState<StockTransferScreen> {
  final List<_Line> _lines = <_Line>[_Line()];
  final TextEditingController _note = TextEditingController();
  String? _toStore;
  bool _tried = false;
  bool _busy = false;
  String? _error;
  StockWriteResult? _done;

  @override
  void dispose() {
    for (final l in _lines) {
      l.qty.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  List<BatchQty?> get _drafts => <BatchQty?>[
    for (final l in _lines)
      l.batch == null
          ? null
          : BatchQty(batch: l.batch!, qty: double.tryParse(l.qty.text) ?? 0),
  ];

  Future<void> _submit() async {
    final l10n = CoreLocalizations.of(context);
    setState(() {
      _tried = true;
      _error = null;
    });
    final store = ref.read(activeStoreProvider);
    if (_toStore == null || store == null) return;
    if (validateTransfer(_drafts).isNotEmpty) return;
    setState(() => _busy = true);
    final result = await ref
        .read(storeApiProvider)
        .transferStock(
          fromStoreId: store.id,
          toStoreId: _toStore!,
          lines: <BatchQty>[for (final d in _drafts) d!],
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _done = result.value;
        ref.invalidate(stockRowsProvider);
      } else {
        final f = result.failure!;
        _error = f.isOffline
            ? l10n.storeOfflineTitle
            : switch (f.code) {
                'negative_stock' => l10n.storeNegativeStock,
                'transfer_source_not_allowed' =>
                  l10n.storeTransferSourceNotAllowed,
                'transfer_destination_not_allowed' =>
                  l10n.storeTransferDestinationNotAllowed,
                _ => l10n.storeErrorHelp,
              };
        if (f.code == 'transfer_destination_not_allowed') {
          _toStore = null;
          ref.invalidate(transferDestinationsProvider);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final role = ref.watch(storeRoleProvider);
    final active = ref.watch(activeStoreProvider);
    final destinations = ref.watch(transferDestinationsProvider).value;
    final stores = <TransferDestination>[
      for (final s in destinations?.value ?? const <TransferDestination>[])
        if (s.id != active?.id) s,
    ];
    final destinationsFailure = destinations?.failure;
    final String noStores =
        destinationsFailure?.code == 'transfer_source_not_allowed'
        ? l10n.storeTransferSourceNotAllowed
        : destinationsFailure?.isOffline ?? false
        ? l10n.storeOfflineTitle
        : l10n.storeNoOtherStores;
    final rows =
        ref.watch(stockRowsProvider).value?.value ?? const <StockRow>[];
    final problems = _tried
        ? validateTransfer(_drafts)
        : const <int, Set<LineProblem>>{};
    return StoreShell(
      section: StoreSection.stock,
      title: l10n.storeTransferTitle,
      showBack: true,
      body: !role.canMoveStock
          ? EmptyState(
              icon: Icons.lock_outline,
              title: l10n.storeNotAllowedTitle,
              help: l10n.storeReadOnlyBanner,
            )
          : _done != null
          ? ListView(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              children: <Widget>[
                StoreCard(
                  key: const Key('transfer-done'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.check_circle,
                        color: app.palette.statusSuccess,
                        size: Tokens.space12,
                      ),
                      Text(l10n.storeTransferDone, style: app.text.title),
                      Text(
                        stores
                                .where((s) => s.id == _toStore)
                                .map((s) => s.name)
                                .firstOrNull ??
                            '',
                        style: app.text.body,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              children: <Widget>[
                if (destinations == null)
                  const LinearProgressIndicator(key: Key('transfer-to-loading'))
                else if (stores.isEmpty)
                  Text(
                    noStores,
                    key: const Key('transfer-no-stores'),
                    style: app.text.body.copyWith(
                      color: app.palette.statusWarning,
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: const Key('transfer-to'),
                    initialValue: _toStore,
                    decoration: InputDecoration(
                      labelText: l10n.storeToStore,
                      errorText: _tried && _toStore == null
                          ? l10n.storeToStoreRequired
                          : null,
                    ),
                    isExpanded: true,
                    items: <DropdownMenuItem<String>>[
                      for (final s in stores)
                        DropdownMenuItem<String>(
                          value: s.id,
                          child: Text(
                            <String>[
                              s.name,
                              if (s.district.isNotEmpty) s.district,
                              if (s.distanceM != null)
                                l10n.storeDistanceKm(
                                  (s.distanceM! / 1000).toStringAsFixed(1),
                                ),
                            ].join(' · '),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _toStore = v),
                  ),
                const SizedBox(height: Tokens.space4),
                for (var i = 0; i < _lines.length; i++) ...<Widget>[
                  _lineCard(context, i, rows, problems[i] ?? const {}),
                  const SizedBox(height: Tokens.space3),
                ],
                AppButton(
                  key: const Key('transfer-add-line'),
                  label: l10n.storeAddLine,
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => setState(() => _lines.add(_Line())),
                ),
                const SizedBox(height: Tokens.space3),
                TextField(
                  key: const Key('transfer-note'),
                  controller: _note,
                  decoration: InputDecoration(labelText: l10n.storeNote),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: Tokens.space3),
                  Text(
                    _error!,
                    key: const Key('transfer-error'),
                    style: app.text.body.copyWith(
                      color: app.palette.statusDanger,
                    ),
                  ),
                ],
                const SizedBox(height: Tokens.space4),
                AppButton(
                  key: const Key('transfer-submit'),
                  label: l10n.storeTransferSubmit,
                  icon: Icons.local_shipping_outlined,
                  loading: _busy,
                  onPressed: stores.isEmpty ? null : _submit,
                ),
              ],
            ),
    );
  }

  Widget _lineCard(
    BuildContext context,
    int i,
    List<StockRow> rows,
    Set<LineProblem> problems,
  ) {
    final l10n = CoreLocalizations.of(context);
    final app = context.app;
    final line = _lines[i];
    final row = rows.where((r) => r.skuId == line.skuId).firstOrNull;
    final batches = row == null
        ? const <StockBatch>[]
        : <StockBatch>[
            for (final b in fefo(row.batches))
              if (b.available > 0) b,
          ];
    final suggested = row == null
        ? null
        : suggestFefo(row.batches, 1).firstOrNull?.batch;
    return StoreCard(
      key: Key('transfer-line-$i'),
      title: '${l10n.storeSku} ${i + 1}',
      trailing: _lines.length > 1
          ? IconButton(
              tooltip: l10n.storeRemoveLine,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _lines.removeAt(i)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DropdownButtonFormField<String>(
            key: Key('transfer-sku-$i'),
            initialValue: line.skuId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.storeFindSku,
              errorText: problems.contains(LineProblem.missing)
                  ? l10n.storeSkuRequired
                  : null,
            ),
            items: <DropdownMenuItem<String>>[
              for (final r in rows)
                if (r.available > 0)
                  DropdownMenuItem<String>(
                    value: r.skuId,
                    child: Text(
                      skuTitle(r.item, r.skuId),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
            onChanged: (id) => setState(() {
              line.skuId = id;
              final r = rows.firstWhere((x) => x.skuId == id);
              line.batch = suggestFefo(r.batches, 1).firstOrNull?.batch;
            }),
          ),
          const SizedBox(height: Tokens.space2),
          DropdownButtonFormField<String>(
            key: Key('transfer-batch-$i-${line.skuId}'),
            initialValue: line.batch?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.storeChooseBatch),
            items: <DropdownMenuItem<String>>[
              for (final b in batches)
                DropdownMenuItem<String>(
                  value: b.id,
                  child: Text(
                    '${l10n.storeBatch(b.batchNo)} · ${b.expiry == null ? l10n.storeNoExpiry : l10n.storeExpires(formatDateIst(b.expiry!))} · ${l10n.storeAvailableQty(formatQty(b.available))}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => setState(
              () => line.batch = batches.firstWhere((b) => b.id == id),
            ),
          ),
          if (line.batch != null && line.batch!.id == suggested?.id)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.space1),
              child: StoreChip(
                key: Key('transfer-fefo-$i'),
                label: l10n.storeFefoSuggested,
                color: app.palette.statusSuccess,
                icon: Icons.auto_awesome_outlined,
              ),
            ),
          const SizedBox(height: Tokens.space2),
          TextField(
            key: Key('transfer-qty-$i'),
            controller: line.qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.storeQuantity,
              helperText: line.batch == null
                  ? null
                  : l10n.storeAvailableQty(formatQty(line.batch!.available)),
              errorText: problems.contains(LineProblem.overAvailable)
                  ? l10n.storeQtyTooHigh(formatQty(line.batch!.available))
                  : problems.contains(LineProblem.qty)
                  ? l10n.storeQtyRequired
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
