import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'wizard_copy.dart';

/// A20 Farmer list: search (name, phone last digits, village), village and
/// crop filters, `FarmerCard`s from the local tables (offline), FAB to A21.
class FarmerListScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const FarmerListScreen({super.key});

  @override
  ConsumerState<FarmerListScreen> createState() => _FarmerListScreenState();
}

class _FarmerListScreenState extends ConsumerState<FarmerListScreen> {
  FarmerListFilter _filter = const FarmerListFilter();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final rows = ref.watch(farmerListProvider(_filter));
    final villages = ref.watch(villagesProvider).value ?? const <Village>[];
    final crops = ref.watch(cropsProvider).value ?? CropRef.pilotFallback;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.farmersTitle),
        actions: <Widget>[
          SyncStatusPillLive(onTap: () => context.push(AppRoutes.syncDetails)),
          const SizedBox(width: Tokens.space3),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('farmers-add'),
        onPressed: () => context.push(AppRoutes.addFarmer),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(l10n.farmersAddFarmer),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.spaceScreenPadding,
                Tokens.space3,
                Tokens.spaceScreenPadding,
                0,
              ),
              child: TextField(
                key: const Key('farmers-search'),
                onChanged: (q) =>
                    setState(() => _filter = _filter.copyWith(query: q)),
                style: app.text.body,
                decoration: InputDecoration(
                  hintText: l10n.farmersSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            SizedBox(
              height: Tokens.sizeTouchTargetMin + Tokens.space3,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.spaceScreenPadding,
                  vertical: Tokens.space2,
                ),
                children: <Widget>[
                  _FilterMenu<Village>(
                    key: const Key('farmers-filter-village'),
                    label: l10n.farmersFilterVillage,
                    allLabel: l10n.farmersFilterAll,
                    options: villages,
                    labelOf: (v) => v.name,
                    idOf: (v) => v.id,
                    selectedId: _filter.villageId,
                    onSelected: (id) => setState(
                      () => _filter = _filter.copyWith(
                        villageId: id,
                        clearVillage: id == null,
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.space2),
                  _FilterMenu<CropRef>(
                    key: const Key('farmers-filter-crop'),
                    label: l10n.farmersFilterCrop,
                    allLabel: l10n.farmersFilterAll,
                    options: crops,
                    labelOf: (c) => cropName(context, c),
                    idOf: (c) => c.id,
                    selectedId: _filter.cropId,
                    onSelected: (id) => setState(
                      () => _filter = _filter.copyWith(
                        cropId: id,
                        clearCrop: id == null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorState(onRetry: () => setState(() {})),
                data: (farmers) {
                  if (farmers.isEmpty) {
                    return _filter.isEmpty
                        ? EmptyState(
                            icon: Icons.people_outline,
                            title: l10n.farmersEmptyTitle,
                            help: l10n.farmersEmptyHelp,
                            actionLabel: l10n.farmersAddFarmer,
                            onAction: () => context.push(AppRoutes.addFarmer),
                          )
                        : EmptyState(
                            icon: Icons.search_off,
                            title: l10n.farmersNoResults,
                            help: l10n.farmersEmptyHelp,
                          );
                  }
                  return ListView.separated(
                    key: const Key('farmers-list'),
                    padding: const EdgeInsets.fromLTRB(
                      Tokens.spaceScreenPadding,
                      Tokens.space2,
                      Tokens.spaceScreenPadding,
                      Tokens.space12 * 2,
                    ),
                    itemCount: farmers.length + 1,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Tokens.space3),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Text(
                          l10n.farmersCount(farmers.length),
                          style: app.text.caption.copyWith(
                            color: p.textSecondary,
                          ),
                        );
                      }
                      final f = farmers[i - 1];
                      return FarmerCard(
                        key: Key('farmer-card-${f.id}'),
                        name: f.name,
                        village: f.villageName,
                        crops: <CropChipData>[
                          for (final c in f.crops)
                            CropChipData(name: cropName(context, c)),
                        ],
                        pendingSync: f.pendingSync,
                        attention: f.rejected,
                        onTap: () => context.push(AppRoutes.farmerPath(f.id)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.allLabel,
    required this.options,
    required this.labelOf,
    required this.idOf,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final String label;
  final String allLabel;
  final List<T> options;
  final String Function(T) labelOf;
  final String Function(T) idOf;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final selected = options.where((o) => idOf(o) == selectedId).firstOrNull;
    final active = selected != null;
    // PopupMenuButton ignores a null value, so "All" carries a sentinel.
    const all = '__all__';
    return PopupMenuButton<String>(
      onSelected: (v) => onSelected(v == all ? null : v),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: all, child: Text(allLabel)),
        for (final o in options)
          PopupMenuItem<String>(value: idOf(o), child: Text(labelOf(o))),
      ],
      child: Material(
        color: active ? app.tint(p.primaryContainer) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
          side: BorderSide(
            color: active ? p.primary : p.border,
            width: app.borderWidth,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space3,
            vertical: Tokens.space2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.filter_list,
                size: Tokens.space4,
                color: active ? p.primary : p.textSecondary,
              ),
              const SizedBox(width: Tokens.space1),
              Text(
                active ? '$label: ${labelOf(selected)}' : label,
                style: app.text.label.copyWith(
                  color: active ? p.primary : p.text,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: active ? p.primary : p.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
