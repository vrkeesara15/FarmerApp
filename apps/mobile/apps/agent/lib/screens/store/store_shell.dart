import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'store_routes.dart';

/// Store-mode sections in the rail / drawer.
enum StoreSection {
  /// S01.
  home,

  /// S02 / S03 / S04.
  pos,

  /// S05.
  queue,

  /// S06 / S07 / S08.
  stock,

  /// S09.
  credit,

  /// S10.
  dayClose,
}

/// Sections [role] can open.
List<StoreSection> sectionsFor(StoreRole role) => <StoreSection>[
  StoreSection.home,
  if (role.canSell) StoreSection.pos,
  StoreSection.queue,
  StoreSection.stock,
  if (role.canApproveCredit || role.canSetCreditLimit) StoreSection.credit,
  StoreSection.dayClose,
];

String _label(CoreLocalizations l10n, StoreSection s) => switch (s) {
  StoreSection.home => l10n.storeNavHome,
  StoreSection.pos => l10n.storeNavPos,
  StoreSection.queue => l10n.storeNavQueue,
  StoreSection.stock => l10n.storeNavStock,
  StoreSection.credit => l10n.storeNavCredit,
  StoreSection.dayClose => l10n.storeNavDayClose,
};

IconData _icon(StoreSection s) => switch (s) {
  StoreSection.home => Icons.storefront_outlined,
  StoreSection.pos => Icons.point_of_sale_outlined,
  StoreSection.queue => Icons.inventory_outlined,
  StoreSection.stock => Icons.warehouse_outlined,
  StoreSection.credit => Icons.menu_book_outlined,
  StoreSection.dayClose => Icons.lock_clock_outlined,
};

String _route(StoreSection s) => switch (s) {
  StoreSection.home => StoreRoutes.home,
  StoreSection.pos => StoreRoutes.pos,
  StoreSection.queue => StoreRoutes.queue,
  StoreSection.stock => StoreRoutes.stock,
  StoreSection.credit => StoreRoutes.credit,
  StoreSection.dayClose => StoreRoutes.dayClose,
};

/// Store-mode frame: role gate, NavigationRail at >= 700 dp (tablet
/// portrait 800 x 1280) or a drawer on phones, store switcher, offline and
/// read-only banners.
class StoreShell extends ConsumerWidget {
  /// Creates the frame.
  const StoreShell({
    required this.section,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.bottom,
    this.floatingActionButton,
    this.showBack = false,
    super.key,
  });

  /// Selected section.
  final StoreSection section;

  /// App bar title.
  final String title;

  /// Content.
  final Widget body;

  /// App bar actions.
  final List<Widget> actions;

  /// App bar bottom (tabs).
  final PreferredSizeWidget? bottom;

  /// FAB.
  final Widget? floatingActionButton;

  /// Back arrow instead of the menu (sub-screens).
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final user = ref.watch(storeUserProvider);
    final role = ref.watch(storeRoleProvider);
    if (user.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!role.hasStoreMode) {
      return Scaffold(
        key: const Key('store-not-allowed'),
        appBar: AppBar(title: Text(l10n.storeModeTitle)),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: l10n.storeNotAllowedTitle,
          help: l10n.storeNotAllowedHelp,
        ),
      );
    }
    final twoPane = isStoreTwoPane(context);
    final sections = sectionsFor(role);
    final offline = ref.watch(offlineProvider);
    final content = Column(
      children: <Widget>[
        if (offline) const OfflineBanner(),
        if (role.readOnly) const _ReadOnlyBanner(),
        Expanded(child: body),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !twoPane || showBack,
        leading: showBack ? BackButton(onPressed: () => _back(context)) : null,
        title: Text(title),
        actions: <Widget>[
          ...actions,
          const _StoreSwitcher(),
          IconButton(
            key: const Key('store-settings'),
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(StoreRoutes.settings),
          ),
        ],
        bottom: bottom,
      ),
      drawer: twoPane || showBack
          ? null
          : Drawer(
              key: const Key('store-drawer'),
              child: SafeArea(
                child: ListView(
                  children: <Widget>[
                    for (final s in sections)
                      ListTile(
                        key: Key('store-nav-${s.name}'),
                        leading: Icon(_icon(s)),
                        title: Text(_label(l10n, s)),
                        selected: s == section,
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(_route(s));
                        },
                      ),
                  ],
                ),
              ),
            ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: twoPane
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  NavigationRail(
                    key: const Key('store-rail'),
                    labelType: NavigationRailLabelType.all,
                    selectedIndex: sections.contains(section)
                        ? sections.indexOf(section)
                        : null,
                    onDestinationSelected: (i) =>
                        context.go(_route(sections[i])),
                    destinations: <NavigationRailDestination>[
                      for (final s in sections)
                        NavigationRailDestination(
                          icon: Icon(_icon(s), key: Key('store-nav-${s.name}')),
                          label: Text(_label(l10n, s)),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_route(section));
    }
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Container(
      key: const Key('store-read-only'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space4,
        vertical: Tokens.space2,
      ),
      color: app.tint(p.statusInfoContainer),
      child: Row(
        children: <Widget>[
          Icon(Icons.visibility_outlined, color: p.statusInfo),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Text(
              CoreLocalizations.of(context).storeReadOnlyBanner,
              style: app.text.label.copyWith(color: p.statusInfo),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreSwitcher extends ConsumerWidget {
  const _StoreSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stores =
        ref.watch(storesProvider).value?.value ?? const <StoreBrief>[];
    final active = ref.watch(activeStoreProvider);
    if (stores.length < 2) {
      if (active == null || active.name.isEmpty) return const SizedBox.shrink();
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
          child: Text(active.name, style: context.app.text.label),
        ),
      );
    }
    return PopupMenuButton<String>(
      key: const Key('store-switcher'),
      tooltip: CoreLocalizations.of(context).storeSwitchStore,
      onSelected: (id) => ref.read(selectedStoreProvider.notifier).select(id),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final s in stores)
          CheckedPopupMenuItem<String>(
            value: s.id,
            checked: s.id == active?.id,
            child: Text(s.name),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(active?.name ?? '', style: context.app.text.label),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Renders a store call: skeletons while loading, offline / error states
/// with retry, else [builder].
class StoreResultView<T> extends StatelessWidget {
  /// Creates the view.
  const StoreResultView({
    required this.value,
    required this.builder,
    required this.onRetry,
    super.key,
  });

  /// The provider value.
  final AsyncValue<StoreResult<T>> value;

  /// Content.
  final Widget Function(T data) builder;

  /// Retry.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final result = value.value;
    if (result == null) {
      return const Padding(
        padding: EdgeInsets.all(Tokens.spaceScreenPadding),
        child: Skeletons.list(),
      );
    }
    if (!result.ok) {
      final offline = result.failure!.isOffline;
      return ErrorState(
        key: Key(offline ? 'store-offline' : 'store-error'),
        title: offline ? l10n.storeOfflineTitle : l10n.storeErrorTitle,
        help: offline ? l10n.storeOfflineHelp : l10n.storeErrorHelp,
        onRetry: onRetry,
      );
    }
    return builder(result.value as T);
  }
}

/// A bordered card section with a title.
class StoreCard extends StatelessWidget {
  /// Creates the card.
  const StoreCard({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(Tokens.space4),
    super.key,
  });

  /// Title.
  final String? title;

  /// Title-row trailing widget.
  final Widget? trailing;

  /// Content.
  final Widget child;

  /// Padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Container(
      decoration: BoxDecoration(
        color: app.palette.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(title!, style: app.text.heading)),
                ?trailing,
              ],
            ),
            const SizedBox(height: Tokens.space3),
          ],
          child,
        ],
      ),
    );
  }
}

/// Label on the left, value on the right.
class StoreAmountRow extends StatelessWidget {
  /// Creates the row.
  const StoreAmountRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.color,
    super.key,
  });

  /// Label.
  final String label;

  /// Pre-formatted value.
  final String value;

  /// Bold total row.
  final bool strong;

  /// Value colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final style = strong ? app.text.heading : app.text.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space1),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: style.copyWith(
                color: strong ? null : app.palette.textSecondary,
              ),
            ),
          ),
          Text(value, style: style.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Status chip.
class StoreChip extends StatelessWidget {
  /// Creates the chip.
  const StoreChip({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  /// Text.
  final String label;

  /// Foreground colour.
  final Color color;

  /// Optional icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: color, width: app.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: Tokens.space4, color: color),
            const SizedBox(width: Tokens.space1),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: app.text.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Localised order status.
String orderStatusLabel(CoreLocalizations l10n, OrderStatus s) => switch (s) {
  OrderStatus.draft || OrderStatus.placed => l10n.storeStatusPlaced,
  OrderStatus.reserved => l10n.storeStatusReserved,
  OrderStatus.packed => l10n.storeStatusPacked,
  OrderStatus.ready => l10n.storeStatusReady,
  OrderStatus.handedOver => l10n.storeStatusHandedOver,
  OrderStatus.delivered => l10n.storeStatusDelivered,
  OrderStatus.cancelled => l10n.storeStatusCancelled,
};

/// Localised queue tab.
String queueTabLabel(CoreLocalizations l10n, QueueTab t) => switch (t) {
  QueueTab.fresh => l10n.storeTabNew,
  QueueTab.packing => l10n.storeTabPacking,
  QueueTab.ready => l10n.storeTabReady,
  QueueTab.handedOver => l10n.storeTabHandedOver,
};

/// Localised payment mode.
String saleModeLabel(CoreLocalizations l10n, SaleMode m) => switch (m) {
  SaleMode.upiQr => l10n.storeModeUpi,
  SaleMode.card => l10n.storeModeCard,
  SaleMode.cash => l10n.storeModeCash,
  SaleMode.credit => l10n.storeModeCredit,
};

/// Localised product category.
String categoryLabel(CoreLocalizations l10n, String c) => switch (c) {
  'seed' => l10n.storeCategorySeed,
  'fertiliser' => l10n.storeCategoryFertiliser,
  'pesticide' => l10n.storeCategoryPesticide,
  'fungicide' => l10n.storeCategoryFungicide,
  'herbicide' => l10n.storeCategoryHerbicide,
  'growth' => l10n.storeCategoryGrowth,
  'tool' => l10n.storeCategoryTool,
  _ => l10n.storeCategoryOther,
};

/// Product categories in display order.
const List<String> storeCategories = <String>[
  'seed',
  'fertiliser',
  'pesticide',
  'fungicide',
  'herbicide',
  'growth',
  'tool',
  'other',
];

/// `Name pack` for a SKU, or its id when the catalogue does not have it.
String skuTitle(StoreItem? item, String skuId) =>
    item == null ? skuId : '${item.name} ${item.packLabel}';

/// Shows a snackbar.
void storeSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
