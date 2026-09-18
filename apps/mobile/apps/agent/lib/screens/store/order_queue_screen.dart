import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store_shell.dart';

/// How often S05 refreshes while it is on screen.
const Duration queueRefreshInterval = Duration(seconds: 30);

/// S05 Order queue: tabs New / Packing / Ready / Handed over with counts;
/// actions follow the server state machine (reserve -> packed -> ready ->
/// handed over / delivered, cancel with a reason); transitions the server
/// would refuse are disabled. Pull to refresh, and every 30 s while visible.
class OrderQueueScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const OrderQueueScreen({super.key});

  @override
  ConsumerState<OrderQueueScreen> createState() => _OrderQueueScreenState();
}

class _OrderQueueScreenState extends ConsumerState<OrderQueueScreen> {
  Timer? _timer;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      queueRefreshInterval,
      (_) => ref.invalidate(orderQueueProvider),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(orderQueueProvider);
    await ref.read(orderQueueProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final value = ref.watch(orderQueueProvider);
    final orders = value.value?.value ?? const <QueueOrder>[];
    int count(QueueTab t) =>
        orders.where((o) => t.statuses.contains(o.status)).length;
    return DefaultTabController(
      length: QueueTab.values.length,
      child: StoreShell(
        section: StoreSection.queue,
        title: l10n.storeQueueTitle,
        bottom: TabBar(
          isScrollable: !isStoreTwoPane(context),
          tabs: <Widget>[
            for (final t in QueueTab.values)
              Tab(
                key: Key('queue-tab-${t.name}'),
                text: l10n.storeTabWithCount(queueTabLabel(l10n, t), count(t)),
              ),
          ],
        ),
        body: StoreResultView<List<QueueOrder>>(
          value: value,
          onRetry: _refresh,
          builder: (all) {
            QueueOrder? selected;
            for (final o in all) {
              if (o.id == _selected) selected = o;
            }
            final twoPane = isStoreTwoPane(context);
            final lists = TabBarView(
              children: <Widget>[
                for (final t in QueueTab.values)
                  _QueueList(
                    tab: t,
                    orders: <QueueOrder>[
                      for (final o in all)
                        if (t.statuses.contains(o.status)) o,
                    ],
                    selectedId: _selected,
                    onRefresh: _refresh,
                    onTap: (o) {
                      setState(() => _selected = o.id);
                      if (!twoPane) _showSheet(o);
                    },
                  ),
              ],
            );
            if (!twoPane) return lists;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 5, child: lists),
                VerticalDivider(width: 1, color: context.app.palette.border),
                Expanded(
                  flex: 4,
                  child: selected == null
                      ? EmptyState(
                          icon: Icons.touch_app_outlined,
                          title: l10n.storeSelectOrder,
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(
                            Tokens.spaceScreenPadding,
                          ),
                          child: OrderDetail(
                            key: Key('queue-detail-${selected.id}'),
                            order: selected,
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showSheet(QueueOrder order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: OrderDetail(
            order: order,
            onDone: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({
    required this.tab,
    required this.orders,
    required this.selectedId,
    required this.onRefresh,
    required this.onTap,
  });

  final QueueTab tab;
  final List<QueueOrder> orders;
  final String? selectedId;
  final Future<void> Function() onRefresh;
  final ValueChanged<QueueOrder> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final names = ref.watch(storeFarmerNamesProvider).value ?? const {};
    final catalog = <String, StoreItem>{
      for (final i
          in ref.watch(storeCatalogProvider).value?.value ??
              const <StoreItem>[])
        i.skuId: i,
    };
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: orders.isEmpty
          ? ListView(
              children: <Widget>[
                EmptyState(
                  key: Key('queue-empty-${tab.name}'),
                  title: l10n.storeQueueEmpty,
                  help: l10n.storeQueueEmptyHelp,
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: Tokens.space3),
              itemBuilder: (context, i) => _OrderCard(
                order: orders[i],
                farmer: _farmerLabel(l10n, names, orders[i]),
                itemsLine: _itemsLine(catalog, orders[i]),
                selected: orders[i].id == selectedId,
                onTap: () => onTap(orders[i]),
              ),
            ),
    );
  }
}

String _farmerLabel(
  CoreLocalizations l10n,
  Map<String, String> names,
  QueueOrder o,
) {
  final id = o.farmerId;
  if (id == null) return l10n.storeBuyerWalkIn;
  final name = names[id];
  if (name != null && name.isNotEmpty) return name;
  final short = id.length <= 6 ? id : id.substring(id.length - 6);
  return l10n.storeFarmerUnknown(short.toUpperCase());
}

String _itemsLine(Map<String, StoreItem> catalog, QueueOrder o) => o.lines
    .map((l) {
      final item = catalog[l.skuId];
      final name = item == null ? l.skuId : '${item.name} ${item.packLabel}';
      return '$name × ${formatQty(l.qty)}';
    })
    .join(', ');

String _channelLabel(CoreLocalizations l10n, String c) => switch (c) {
  'officer' => l10n.storeChannelOfficer,
  'farmer_app' => l10n.storeChannelFarmerApp,
  _ => l10n.storeChannelPos,
};

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.farmer,
    required this.itemsLine,
    required this.selected,
    required this.onTap,
  });

  final QueueOrder order;
  final String farmer;
  final String itemsLine;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Material(
      key: Key('queue-order-${order.id}'),
      color: selected ? app.tint(p.primaryContainer) : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: BorderSide(
          color: selected ? p.primary : p.border,
          width: selected ? app.borderWidth + 1 : app.borderWidth,
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
                      l10n.storeOrderRef(order.shortRef),
                      style: app.text.heading,
                    ),
                  ),
                  StoreChip(
                    label: orderStatusLabel(l10n, order.status),
                    color: p.statusInfo,
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space1),
              Text(farmer, style: app.text.label),
              Text(
                itemsLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: app.text.caption.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: Tokens.space1),
              Row(
                children: <Widget>[
                  Icon(
                    order.fulfilment == 'delivery'
                        ? Icons.local_shipping_outlined
                        : Icons.storefront_outlined,
                    size: Tokens.space4,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: Tokens.space1),
                  Expanded(
                    child: Text(
                      '${_channelLabel(l10n, order.channel)} · '
                      '${order.fulfilment == 'delivery' ? l10n.storeFulfilmentDelivery : l10n.storeFulfilmentPickup}'
                      '${order.placedAt == null ? '' : ' · ${formatDateTimeIst(order.placedAt!)}'}',
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                  ),
                  Text(formatInr(order.totalPaise), style: app.text.label),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Order lines and the transition buttons (S05 detail pane / sheet).
class OrderDetail extends ConsumerStatefulWidget {
  /// Creates the detail.
  const OrderDetail({required this.order, this.onDone, super.key});

  /// The order.
  final QueueOrder order;

  /// Called after a successful change (closes the phone sheet).
  final VoidCallback? onDone;

  @override
  ConsumerState<OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends ConsumerState<OrderDetail> {
  bool _busy = false;

  Future<void> _move(OrderStatus to, {String? note}) async {
    final l10n = CoreLocalizations.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(storeApiProvider)
        .setOrderStatus(widget.order.id, to, note: note);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      storeSnack(context, l10n.storeOrderMoved(orderStatusLabel(l10n, to)));
      ref.invalidate(orderQueueProvider);
      widget.onDone?.call();
    } else {
      storeSnack(
        context,
        result.failure!.isOffline
            ? l10n.storeOfflineTitle
            : result.failure!.code == 'insufficient_stock'
            ? l10n.storeNegativeStock
            : l10n.storeTransitionFailed,
      );
    }
  }

  Future<void> _cancel() async {
    final l10n = CoreLocalizations.of(context);
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(l10n.storeActionCancel),
          content: TextField(
            key: const Key('queue-cancel-reason'),
            controller: controller,
            autofocus: true,
            onChanged: (_) => setDialog(() {}),
            decoration: InputDecoration(labelText: l10n.storeCancelReason),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.storeKeepOrder),
            ),
            FilledButton(
              key: const Key('queue-cancel-confirm'),
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(l10n.storeActionCancel),
            ),
          ],
        ),
      ),
    );
    // The dialog's exit animation may still read the controller; it holds
    // no listeners, so it is left to the garbage collector.
    if (reason != null && mounted) {
      await _move(OrderStatus.cancelled, note: reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final order = widget.order;
    final role = ref.watch(storeRoleProvider);
    final tab = QueueTab.of(order.status);
    final catalog = <String, StoreItem>{
      for (final i
          in ref.watch(storeCatalogProvider).value?.value ??
              const <StoreItem>[])
        i.skuId: i,
    };
    String actionLabel(OrderStatus s) => switch (s) {
      OrderStatus.reserved => l10n.storeActionReserve,
      OrderStatus.packed => l10n.storeActionPack,
      OrderStatus.ready => l10n.storeActionReady,
      OrderStatus.handedOver => l10n.storeActionHandOver,
      OrderStatus.delivered => l10n.storeActionDeliver,
      _ => l10n.storeActionCancel,
    };
    final actions = tab == null ? const <OrderStatus>[] : queueActions(tab);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.storeOrderRef(order.shortRef), style: app.text.title),
        const SizedBox(height: Tokens.space1),
        StoreChip(
          label: orderStatusLabel(l10n, order.status),
          color: p.statusInfo,
        ),
        const SizedBox(height: Tokens.space3),
        for (final l in order.lines)
          StoreAmountRow(
            label:
                '${skuTitle(catalog[l.skuId], l.skuId)} × ${formatQty(l.qty)}',
            value: formatInr(l.lineTotalPaise),
          ),
        Divider(color: p.border),
        StoreAmountRow(
          label: l10n.storeTotal,
          value: formatInr(order.totalPaise),
          strong: true,
        ),
        if (order.notes != null && order.notes!.isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          Text(order.notes!, style: app.text.body),
        ],
        if (role.canMoveQueue && tab != QueueTab.handedOver) ...<Widget>[
          const SizedBox(height: Tokens.space4),
          for (final to in actions) ...<Widget>[
            AppButton(
              key: Key('queue-action-${to.wire}'),
              label: actionLabel(to),
              size: AppButtonSize.medium,
              loading: _busy,
              onPressed: canTransition(order.status, to)
                  ? () => _move(to)
                  : null,
            ),
            const SizedBox(height: Tokens.space2),
          ],
          AppButton(
            key: const Key('queue-action-cancelled'),
            label: l10n.storeActionCancel,
            variant: AppButtonVariant.destructive,
            size: AppButtonSize.medium,
            onPressed:
                canTransition(order.status, OrderStatus.cancelled) && !_busy
                ? _cancel
                : null,
          ),
        ],
      ],
    );
  }
}
