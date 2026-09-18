import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'store_routes.dart';
import 'store_shell.dart';

/// S01 Store home: today's sales (total and by mode), order-queue counts,
/// low stock, day-close status and the primary counter actions.
class StoreHomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const StoreHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final role = ref.watch(storeRoleProvider);
    final summary = ref.watch(daySummaryProvider);
    Future<void> refresh() async {
      ref
        ..invalidate(daySummaryProvider)
        ..invalidate(orderQueueProvider)
        ..invalidate(stockRowsProvider);
      await ref.read(daySummaryProvider.future);
    }

    return StoreShell(
      section: StoreSection.home,
      title: l10n.storeHomeTitle,
      body: StoreResultView<DaySummary>(
        value: summary,
        onRetry: refresh,
        builder: (s) => RefreshIndicator(
          onRefresh: refresh,
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 600;
              final cards = <Widget>[
                _SalesCard(summary: s),
                const _QueueCard(),
                const _StockCard(),
                _DayCloseCard(summary: s),
              ];
              return ListView(
                key: const Key('store-home'),
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  _Actions(role: role),
                  const SizedBox(height: Tokens.space4),
                  if (wide)
                    for (var i = 0; i < cards.length; i += 2) ...<Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: cards[i]),
                          const SizedBox(width: Tokens.space4),
                          Expanded(child: cards[i + 1]),
                        ],
                      ),
                      const SizedBox(height: Tokens.space4),
                    ]
                  else
                    for (final card in cards) ...<Widget>[
                      card,
                      const SizedBox(height: Tokens.space4),
                    ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.role});

  final StoreRole role;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return Wrap(
      spacing: Tokens.space3,
      runSpacing: Tokens.space3,
      children: <Widget>[
        if (role.canSell)
          AppButton(
            key: const Key('store-action-sale'),
            label: l10n.storeActionNewSale,
            icon: Icons.point_of_sale_outlined,
            expand: false,
            onPressed: () => context.go(StoreRoutes.pos),
          ),
        if (role.canMoveStock) ...<Widget>[
          AppButton(
            key: const Key('store-action-receipt'),
            label: l10n.storeActionReceive,
            icon: Icons.move_to_inbox_outlined,
            variant: AppButtonVariant.secondary,
            expand: false,
            onPressed: () => context.push(StoreRoutes.receipt),
          ),
          AppButton(
            key: const Key('store-action-transfer'),
            label: l10n.storeActionTransfer,
            icon: Icons.local_shipping_outlined,
            variant: AppButtonVariant.secondary,
            expand: false,
            onPressed: () => context.push(StoreRoutes.transfer),
          ),
        ],
        if (role.canCloseDay)
          AppButton(
            key: const Key('store-action-close'),
            label: l10n.storeActionCloseDay,
            icon: Icons.lock_clock_outlined,
            variant: AppButtonVariant.secondary,
            expand: false,
            onPressed: () => context.go(StoreRoutes.dayClose),
          ),
      ],
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return StoreCard(
      key: const Key('store-sales-card'),
      title: l10n.storeTodaySales,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            formatInr(summary.salesPaise),
            key: const Key('store-sales-total'),
            style: app.text.display,
          ),
          Text(
            l10n.storeSalesCount(summary.salesCount),
            style: app.text.caption.copyWith(color: app.palette.textSecondary),
          ),
          const SizedBox(height: Tokens.space2),
          for (final m in SaleMode.values)
            StoreAmountRow(
              key: Key('store-sales-${m.wire}'),
              label: saleModeLabel(l10n, m),
              value: formatInr(summary.amountFor(m)),
            ),
        ],
      ),
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final orders = ref.watch(orderQueueProvider).value?.value;
    int count(QueueTab t) => orders == null
        ? 0
        : orders.where((o) => t.statuses.contains(o.status)).length;
    return StoreCard(
      key: const Key('store-queue-card'),
      title: l10n.storeQueueCounts,
      child: Wrap(
        spacing: Tokens.space2,
        runSpacing: Tokens.space2,
        children: <Widget>[
          for (final t in QueueTab.values)
            SizedBox(
              width: 150,
              child: InkWell(
                key: Key('store-queue-count-${t.name}'),
                onTap: () => context.go(StoreRoutes.queue),
                child: StatTile(
                  value: orders == null ? '–' : '${count(t)}',
                  label: queueTabLabel(l10n, t),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StockCard extends ConsumerWidget {
  const _StockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final rows = ref.watch(stockRowsProvider).value?.value;
    final low = rows?.where((r) => r.isLow).length;
    final expiring = rows?.where((r) => r.isExpiring).length;
    return StoreCard(
      key: const Key('store-stock-card'),
      title: l10n.storeLowStock,
      child: InkWell(
        onTap: () => context.go(StoreRoutes.stock),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.inventory_2_outlined,
                  color: app.palette.statusWarning,
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    low == null ? '–' : l10n.storeLowStockCount(low),
                    key: const Key('store-low-count'),
                    style: app.text.title,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space2),
            Row(
              children: <Widget>[
                Icon(
                  Icons.event_busy_outlined,
                  color: app.palette.statusDanger,
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    expiring == null ? '–' : l10n.storeExpiringCount(expiring),
                    style: app.text.body,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCloseCard extends StatelessWidget {
  const _DayCloseCard({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final close = summary.dayClose;
    final closed = close?.isClosed ?? false;
    return StoreCard(
      key: const Key('store-dayclose-card'),
      title: l10n.storeDayCloseStatus,
      child: InkWell(
        onTap: () => context.go(StoreRoutes.dayClose),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            StoreChip(
              label: closed
                  ? l10n.storeDayClosed(
                      close!.closedAt == null
                          ? ''
                          : formatTimeIst(close.closedAt!),
                    )
                  : close != null
                  ? l10n.storeDayReopened
                  : l10n.storeDayOpen,
              color: closed ? p.statusSuccess : p.statusWarning,
              icon: closed ? Icons.lock_outline : Icons.lock_open_outlined,
            ),
            const SizedBox(height: Tokens.space3),
            StoreAmountRow(
              label: l10n.storeExpectedCash,
              value: formatInr(summary.expectedCashPaise),
            ),
            if (closed)
              StoreAmountRow(
                label: l10n.storeVariance,
                value: formatInr(close!.variancePaise),
                color: close.flagged ? p.statusDanger : null,
              ),
          ],
        ),
      ),
    );
  }
}
