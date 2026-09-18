import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'stock_adjust_dialog.dart';
import 'store_routes.dart';
import 'store_shell.dart';

/// S06 Stock list: SKU rows with on-hand / reserved / available, batches
/// with expiry (within 30 / 60 days highlighted), filters (category, low
/// stock, expiring) and search; write-off and adjustment dialogs.
class StockScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  StockFilter _filter = const StockFilter();
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final role = ref.watch(storeRoleProvider);
    final value = ref.watch(stockRowsProvider);
    final twoPane = isStoreTwoPane(context);
    return StoreShell(
      section: StoreSection.stock,
      title: l10n.storeStockTitle,
      actions: <Widget>[
        if (role.canMoveStock) ...<Widget>[
          IconButton(
            key: const Key('stock-receipt'),
            tooltip: l10n.storeActionReceive,
            icon: const Icon(Icons.move_to_inbox_outlined),
            onPressed: () => context.push(StoreRoutes.receipt),
          ),
          IconButton(
            key: const Key('stock-transfer'),
            tooltip: l10n.storeActionTransfer,
            icon: const Icon(Icons.local_shipping_outlined),
            onPressed: () => context.push(StoreRoutes.transfer),
          ),
        ],
      ],
      body: Column(
        children: <Widget>[
          _Filters(
            filter: _filter,
            onChanged: (f) => setState(() => _filter = f),
          ),
          Expanded(
            child: StoreResultView<List<StockRow>>(
              value: value,
              onRetry: () => ref.invalidate(stockRowsProvider),
              builder: (rows) {
                final shown = _filter.apply(rows);
                StockRow? selected;
                for (final r in rows) {
                  if (r.skuId == _selected) selected = r;
                }
                final list = RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(stockRowsProvider);
                    await ref.read(stockRowsProvider.future);
                  },
                  child: shown.isEmpty
                      ? ListView(
                          children: <Widget>[
                            EmptyState(
                              key: const Key('stock-empty'),
                              icon: Icons.inventory_2_outlined,
                              title: l10n.storeStockEmpty,
                              help: l10n.storeStockEmptyHelp,
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(
                            Tokens.spaceScreenPadding,
                          ),
                          itemCount: shown.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: Tokens.space2),
                          itemBuilder: (context, i) => _StockTile(
                            row: shown[i],
                            selected: shown[i].skuId == _selected,
                            onTap: () {
                              setState(() => _selected = shown[i].skuId);
                              if (!twoPane) _sheet(shown[i]);
                            },
                          ),
                        ),
                );
                if (!twoPane) return list;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 5, child: list),
                    VerticalDivider(
                      width: 1,
                      color: context.app.palette.border,
                    ),
                    Expanded(
                      flex: 4,
                      child: selected == null
                          ? EmptyState(
                              icon: Icons.touch_app_outlined,
                              title: l10n.storeSelectSku,
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(
                                Tokens.spaceScreenPadding,
                              ),
                              child: StockDetail(
                                key: Key('stock-detail-${selected.skuId}'),
                                row: selected,
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
    );
  }

  void _sheet(StockRow row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: StockDetail(row: row),
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.filter, required this.onChanged});

  final StockFilter filter;
  final ValueChanged<StockFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.spaceScreenPadding,
        Tokens.space3,
        Tokens.spaceScreenPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('stock-search'),
            onChanged: (q) => onChanged(filter.copyWith(query: q)),
            decoration: InputDecoration(
              hintText: l10n.storeSearchProducts,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: Tokens.space2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                FilterChip(
                  key: const Key('stock-filter-low'),
                  label: Text(l10n.storeFilterLow),
                  selected: filter.lowOnly,
                  onSelected: (v) => onChanged(filter.copyWith(lowOnly: v)),
                ),
                const SizedBox(width: Tokens.space2),
                FilterChip(
                  key: const Key('stock-filter-expiring'),
                  label: Text(l10n.storeFilterExpiring),
                  selected: filter.expiringOnly,
                  onSelected: (v) =>
                      onChanged(filter.copyWith(expiringOnly: v)),
                ),
                const SizedBox(width: Tokens.space3),
                ChoiceChip(
                  key: const Key('stock-cat-all'),
                  label: Text(l10n.storeCategoryAll),
                  selected: filter.category == null,
                  onSelected: (_) =>
                      onChanged(filter.copyWith(clearCategory: true)),
                ),
                for (final c in storeCategories) ...<Widget>[
                  const SizedBox(width: Tokens.space2),
                  ChoiceChip(
                    key: Key('stock-cat-$c'),
                    label: Text(categoryLabel(l10n, c)),
                    selected: filter.category == c,
                    onSelected: (_) => onChanged(filter.copyWith(category: c)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour and label for an expiry band.
(Color, String)? expiryStyle(
  BuildContext context,
  CoreLocalizations l10n,
  ExpiryBand band,
) {
  final p = context.app.palette;
  return switch (band) {
    ExpiryBand.expired => (p.statusDanger, l10n.storeExpired),
    ExpiryBand.within30 => (p.statusDanger, l10n.storeExpiring30),
    ExpiryBand.within60 => (p.statusWarning, l10n.storeExpiring60),
    ExpiryBand.ok => null,
  };
}

class _StockTile extends StatelessWidget {
  const _StockTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final StockRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final expiry = expiryStyle(context, l10n, row.expiryBand);
    return Material(
      key: Key('stock-row-${row.skuId}'),
      color: selected ? app.tint(p.primaryContainer) : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: BorderSide(
          color: expiry?.$1 ?? (selected ? p.primary : p.border),
          width: expiry != null || selected
              ? app.borderWidth + 1
              : app.borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      skuTitle(row.item, row.skuId),
                      style: app.text.heading,
                    ),
                  ),
                  if (row.item?.ownBrand ?? false) const OwnBrandBadge(),
                ],
              ),
              const SizedBox(height: Tokens.space1),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Qty(label: l10n.storeOnHand, value: row.onHand),
                  ),
                  Expanded(
                    child: _Qty(label: l10n.storeReserved, value: row.reserved),
                  ),
                  Expanded(
                    child: _Qty(
                      key: Key('stock-available-${row.skuId}'),
                      label: l10n.storeAvailable,
                      value: row.available,
                      strong: true,
                    ),
                  ),
                ],
              ),
              if (row.isLow || expiry != null) ...<Widget>[
                const SizedBox(height: Tokens.space2),
                Wrap(
                  spacing: Tokens.space2,
                  children: <Widget>[
                    if (row.isLow)
                      StoreChip(
                        key: Key('stock-low-${row.skuId}'),
                        label: l10n.storeLowStock,
                        color: p.statusWarning,
                        icon: Icons.trending_down,
                      ),
                    if (expiry != null)
                      StoreChip(
                        key: Key('stock-expiry-${row.skuId}'),
                        label: expiry.$2,
                        color: expiry.$1,
                        icon: Icons.event_busy_outlined,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Qty extends StatelessWidget {
  const _Qty({
    required this.label,
    required this.value,
    this.strong = false,
    super.key,
  });

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: app.text.caption.copyWith(color: app.palette.textSecondary),
        ),
        Text(formatQty(value), style: strong ? app.text.title : app.text.body),
      ],
    );
  }
}

/// Batches of one SKU with expiry and the write-off / adjust actions.
class StockDetail extends ConsumerWidget {
  /// Creates the detail.
  const StockDetail({required this.row, super.key});

  /// The SKU row.
  final StockRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final role = ref.watch(storeRoleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(skuTitle(row.item, row.skuId), style: app.text.title),
        const SizedBox(height: Tokens.space3),
        for (final b in row.batches) ...<Widget>[
          Builder(
            builder: (context) {
              final expiry = expiryStyle(
                context,
                l10n,
                expiryBandFor(b.daysToExpiry),
              );
              return Container(
                key: Key('batch-${b.id}'),
                padding: const EdgeInsets.all(Tokens.space3),
                decoration: BoxDecoration(
                  color: expiry == null
                      ? p.surface
                      : app.tint(
                          expiry.$1 == p.statusDanger
                              ? p.statusDangerContainer
                              : p.statusWarningContainer,
                        ),
                  borderRadius: BorderRadius.circular(Tokens.radiusCard),
                  border: Border.all(
                    color: expiry?.$1 ?? p.border,
                    width: app.borderWidth,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l10n.storeBatch(b.batchNo),
                            style: app.text.label,
                          ),
                        ),
                        if (expiry != null)
                          Flexible(
                            child: StoreChip(
                              label: expiry.$2,
                              color: expiry.$1,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      b.expiry == null
                          ? l10n.storeNoExpiry
                          : l10n.storeExpires(formatDateIst(b.expiry!)),
                      style: app.text.caption,
                    ),
                    const SizedBox(height: Tokens.space1),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _Qty(label: l10n.storeOnHand, value: b.onHand),
                        ),
                        Expanded(
                          child: _Qty(
                            label: l10n.storeReserved,
                            value: b.reserved,
                          ),
                        ),
                        Expanded(
                          child: _Qty(
                            label: l10n.storeAvailable,
                            value: b.available,
                            strong: true,
                          ),
                        ),
                      ],
                    ),
                    if (role.canMoveStock) ...<Widget>[
                      const SizedBox(height: Tokens.space2),
                      Wrap(
                        spacing: Tokens.space2,
                        runSpacing: Tokens.space2,
                        children: <Widget>[
                          AppButton(
                            key: Key('batch-writeoff-${b.id}'),
                            label: l10n.storeWriteOff,
                            icon: Icons.delete_sweep_outlined,
                            variant: AppButtonVariant.secondary,
                            size: AppButtonSize.medium,
                            expand: false,
                            onPressed: b.available > 0
                                ? () => showWriteOffDialog(context, ref, b)
                                : null,
                          ),
                          AppButton(
                            key: Key('batch-adjust-${b.id}'),
                            label: l10n.storeAdjust,
                            icon: Icons.fact_check_outlined,
                            variant: AppButtonVariant.tertiary,
                            size: AppButtonSize.medium,
                            expand: false,
                            onPressed: () => showAdjustDialog(context, ref, b),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: Tokens.space2),
        ],
      ],
    );
  }
}

/// Numeric quantity input.
final List<TextInputFormatter> qtyInput = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
];

/// Write-off: reason, qty (<= available), optional photo, note.
Future<void> showWriteOffDialog(
  BuildContext context,
  WidgetRef ref,
  StockBatch batch,
) async {
  final l10n = CoreLocalizations.of(context);
  final done = await showDialog<bool>(
    context: context,
    builder: (context) => _WriteOffDialog(batch: batch),
  );
  if ((done ?? false) && context.mounted) {
    storeSnack(context, l10n.storeSaved);
    ref.invalidate(stockRowsProvider);
  }
}

class _WriteOffDialog extends ConsumerStatefulWidget {
  const _WriteOffDialog({required this.batch});

  final StockBatch batch;

  @override
  ConsumerState<_WriteOffDialog> createState() => _WriteOffDialogState();
}

class _WriteOffDialogState extends ConsumerState<_WriteOffDialog> {
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _note = TextEditingController();
  WriteOffReason _reason = WriteOffReason.damage;
  Uint8List? _photo;
  bool _tried = false;
  bool _busy = false;
  String? _serverError;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final raw = await ref.read(cameraSourceProvider).capture();
    if (raw == null || !mounted) return;
    final processed = await ref.read(storePhotoProcessorProvider)(raw);
    if (!mounted) return;
    setState(() => _photo = processed);
  }

  Future<void> _submit() async {
    final l10n = CoreLocalizations.of(context);
    setState(() => _tried = true);
    final qty = double.tryParse(_qty.text);
    if (validateBatchQty(widget.batch, qty).isNotEmpty) return;
    final store = ref.read(activeStoreProvider);
    if (store == null) return;
    setState(() => _busy = true);
    final api = ref.read(storeApiProvider);
    String? uri;
    if (_photo != null) {
      final up = await api.uploadPhoto(_photo!);
      if (!mounted) return;
      if (!up.ok) {
        setState(() {
          _busy = false;
          _serverError = up.failure!.isOffline
              ? l10n.storeOfflineTitle
              : l10n.storeErrorHelp;
        });
        return;
      }
      uri = up.value;
    }
    final result = await api.writeOff(
      store.id,
      line: BatchQty(batch: widget.batch, qty: qty!),
      reason: _reason,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      photoUri: uri,
    );
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _serverError = result.failure!.isOffline
          ? l10n.storeOfflineTitle
          : result.failure!.code == 'negative_stock'
          ? l10n.storeNegativeStock
          : l10n.storeErrorHelp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final problems = _tried
        ? validateBatchQty(widget.batch, double.tryParse(_qty.text))
        : const <LineProblem>{};
    return AlertDialog(
      key: const Key('writeoff-dialog'),
      title: Text(l10n.storeWriteOffTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.storeBatch(widget.batch.batchNo)),
            Text(l10n.storeAvailableQty(formatQty(widget.batch.available))),
            const SizedBox(height: Tokens.space3),
            Text(l10n.storeReason),
            Wrap(
              spacing: Tokens.space2,
              children: <Widget>[
                for (final r in WriteOffReason.values)
                  ChoiceChip(
                    key: Key('writeoff-reason-${r.name}'),
                    label: Text(switch (r) {
                      WriteOffReason.damage => l10n.storeReasonDamage,
                      WriteOffReason.expiry => l10n.storeReasonExpiry,
                      WriteOffReason.other => l10n.storeReasonOther,
                    }),
                    selected: _reason == r,
                    onSelected: (_) => setState(() => _reason = r),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space3),
            TextField(
              key: const Key('writeoff-qty'),
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: qtyInput,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.storeQuantity,
                errorText: problems.contains(LineProblem.overAvailable)
                    ? l10n.storeQtyTooHigh(formatQty(widget.batch.available))
                    : problems.contains(LineProblem.qty)
                    ? l10n.storeQtyRequired
                    : null,
              ),
            ),
            const SizedBox(height: Tokens.space2),
            TextField(
              key: const Key('writeoff-note'),
              controller: _note,
              decoration: InputDecoration(labelText: l10n.storeNote),
            ),
            const SizedBox(height: Tokens.space2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('writeoff-photo'),
                onPressed: _busy ? null : _takePhoto,
                icon: Icon(
                  _photo == null ? Icons.photo_camera_outlined : Icons.check,
                ),
                label: Text(
                  _photo == null ? l10n.storeAddPhoto : l10n.storePhotoAdded,
                ),
              ),
            ),
            if (_serverError != null)
              Text(
                _serverError!,
                key: const Key('writeoff-error'),
                style: TextStyle(color: context.app.palette.statusDanger),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('writeoff-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.storeWriteOff),
        ),
      ],
    );
  }
}
