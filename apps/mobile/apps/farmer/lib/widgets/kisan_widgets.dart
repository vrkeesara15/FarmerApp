import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

/// Bottom navigation tabs of the farmer app (SPEC 13.3 F10).
enum KisanTab {
  /// F10.
  home,

  /// F20 (crop doctor, later task).
  cropDoctor,

  /// F34.
  orders,

  /// F70.
  me,
}

/// A tab screen: app bar, offline banner, body and the four-tab bottom
/// navigation (icons always paired with labels, NF-009).
class KisanTabScaffold extends ConsumerWidget {
  /// Creates the scaffold.
  const KisanTabScaffold({
    required this.tab,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    super.key,
  });

  /// Selected tab.
  final KisanTab tab;

  /// App bar title.
  final String title;

  /// Content.
  final Widget body;

  /// App bar actions.
  final List<Widget> actions;

  static const Map<KisanTab, String> _paths = <KisanTab, String>{
    KisanTab.home: AppRoutes.home,
    KisanTab.cropDoctor: AppRoutes.cropDoctor,
    KisanTab.orders: AppRoutes.orders,
    KisanTab.me: AppRoutes.me,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final offline = ref.watch(offlineProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (offline) const OfflineBanner(),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('kisan-nav'),
        selectedIndex: tab.index,
        onDestinationSelected: (i) {
          final next = KisanTab.values[i];
          if (next != tab) context.go(_paths[next]!);
        },
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.kisanNavHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.camera_alt_outlined),
            selectedIcon: const Icon(Icons.camera_alt),
            label: l10n.kisanNavCropDoctor,
          ),
          NavigationDestination(
            icon: const Icon(Icons.shopping_bag_outlined),
            selectedIcon: const Icon(Icons.shopping_bag),
            label: l10n.kisanNavOrders,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.kisanNavMe,
          ),
        ],
      ),
    );
  }
}

/// "Updated 19-09-2026, 10:30" under cached data (NF-002); says "Offline"
/// first when the phone has no network.
class AsOfLabel extends ConsumerWidget {
  /// Creates the label.
  const AsOfLabel(this.asOf, {super.key});

  /// When the data was fetched (UTC).
  final DateTime asOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final offline = ref.watch(offlineProvider);
    final when = formatDateTimeIst(asOf);
    return Row(
      key: const Key('as-of'),
      children: <Widget>[
        Icon(
          offline ? Icons.cloud_off_outlined : Icons.history,
          size: Tokens.space4,
          color: app.palette.textSecondary,
        ),
        const SizedBox(width: Tokens.space1),
        Expanded(
          child: Text(
            offline ? l10n.kisanOfflineAsOf(when) : l10n.kisanAsOf(when),
            style: app.text.caption.copyWith(color: app.palette.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// A big tap-only choice (NF-010: no typing): icon above a label, 48 dp+
/// target, selected state with a check.
class ChoiceTile extends StatelessWidget {
  /// Creates the tile.
  const ChoiceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// Pictogram.
  final IconData icon;

  /// Text paired with the icon.
  final String label;

  /// Chosen.
  final bool selected;

  /// Tap handler (null = read-only).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Padding(
              padding: const EdgeInsets.all(Tokens.space2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    selected ? Icons.check_circle : icon,
                    size: Tokens.space8,
                    color: selected ? p.primary : p.textSecondary,
                  ),
                  const SizedBox(height: Tokens.space1),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: app.text.label.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [ChoiceTile]s three per row.
class ChoiceGrid extends StatelessWidget {
  /// Creates the grid.
  const ChoiceGrid({required this.children, this.columns = 3, super.key});

  /// Tiles.
  final List<Widget> children;

  /// Tiles per row.
  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Tokens.space2,
      crossAxisSpacing: Tokens.space2,
      childAspectRatio: 1.05,
      children: children,
    );
  }
}

/// A key instruction with its audio button next to it (NF-009).
class SpokenText extends StatelessWidget {
  /// Creates the row.
  const SpokenText({
    required this.promptId,
    required this.text,
    this.style,
    super.key,
  });

  /// Audio prompt id.
  final String promptId;

  /// Instruction.
  final String text;

  /// Text style (body by default).
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(text, style: style ?? app.text.body),
        AudioButton(promptId: promptId, text: text),
      ],
    );
  }
}

/// Section card with a title row.
class KisanCard extends StatelessWidget {
  /// Creates the card.
  const KisanCard({
    required this.child,
    this.title,
    this.icon,
    this.onTap,
    super.key,
  });

  /// Content.
  final Widget child;

  /// Title.
  final String? title;

  /// Title icon.
  final IconData? icon;

  /// Makes the whole card tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title != null) ...<Widget>[
                Row(
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, color: app.palette.primary),
                      const SizedBox(width: Tokens.space2),
                    ],
                    Expanded(child: Text(title!, style: app.text.heading)),
                    if (onTap != null)
                      Icon(
                        Icons.chevron_right,
                        color: app.palette.textSecondary,
                      ),
                  ],
                ),
                const SizedBox(height: Tokens.space2),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Pictogram for a crop stage.
IconData stageIcon(String? stage) => switch (stage) {
  'sown' => Icons.grass,
  'vegetative' => Icons.eco,
  'flowering' => Icons.local_florist,
  'fruiting' => Icons.spa,
  'maturity' => Icons.agriculture,
  'harvested' => Icons.inventory_2_outlined,
  _ => Icons.help_outline,
};

/// Pictogram for an irrigation type.
IconData irrigationIcon(String? value) => switch (value) {
  'rainfed' => Icons.cloud_outlined,
  'borewell' => Icons.plumbing,
  'canal' => Icons.waves,
  'tank' => Icons.water,
  'open_well' => Icons.radio_button_unchecked,
  'drip' => Icons.water_drop_outlined,
  'sprinkler' => Icons.shower_outlined,
  _ => Icons.help_outline,
};

/// Pictogram for a soil type.
IconData soilIcon(String? value) => switch (value) {
  'black' => Icons.circle,
  'red' => Icons.landscape,
  'sandy' => Icons.grain,
  'loamy' => Icons.terrain,
  'clay' => Icons.layers,
  'alluvial' => Icons.water_damage_outlined,
  'laterite' => Icons.texture,
  _ => Icons.help_outline,
};

/// Crop name in the app language.
String cropName(BuildContext context, List<CropRef> crops, String cropId) {
  final lang = Localizations.localeOf(context).languageCode;
  final crop = crops.where((c) => c.id == cropId).firstOrNull;
  return crop?.nameIn(lang) ?? CoreLocalizations.of(context).kisanCropUnknown;
}

/// Shows a short message at the bottom.
void showKisanMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Runs [onOpen] once when the screen opens (refresh the cached data it
/// shows; the cache is shown meanwhile and stays when offline).
class RefreshOnOpen extends ConsumerStatefulWidget {
  /// Creates the wrapper.
  const RefreshOnOpen({required this.onOpen, required this.child, super.key});

  /// Refresh to run.
  final Future<void> Function(WidgetRef ref) onOpen;

  /// Content.
  final Widget child;

  @override
  ConsumerState<RefreshOnOpen> createState() => _RefreshOnOpenState();
}

class _RefreshOnOpenState extends ConsumerState<RefreshOnOpen> {
  @override
  void initState() {
    super.initState();
    widget.onOpen(ref).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
