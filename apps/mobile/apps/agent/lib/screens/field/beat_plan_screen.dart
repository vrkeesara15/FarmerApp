import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../visits/visit_copy.dart';
import 'field_widgets.dart';

/// A11 Beat plan (FA-018): today's ordered list of farmers and villages
/// with the reasons the system chose them, drag to reorder, add and remove,
/// a map toggle, and "start visit" straight from an item.
///
/// The plan comes from the local `beat_plan` sync entity, so the screen
/// works offline; every edit writes the whole ordered list through the
/// outbox (`PUT /v1/me/beat` semantics).
class BeatPlanScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BeatPlanScreen({super.key});

  @override
  ConsumerState<BeatPlanScreen> createState() => _BeatPlanScreenState();
}

class _BeatPlanScreenState extends ConsumerState<BeatPlanScreen> {
  bool _map = false;

  @override
  void initState() {
    super.initState();
    final date = ref.read(todayIstProvider);
    unawaited(ref.read(fieldRepositoryProvider).refreshBeat(date));
  }

  Future<void> _reorder(BeatPlan plan, int oldIndex, int newIndex) async {
    final items = <BeatItem>[...plan.items];
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    items.insert(target, items.removeAt(oldIndex));
    await ref.read(fieldRepositoryProvider).saveBeat(plan.withItems(items));
  }

  Future<void> _remove(BeatPlan plan, BeatItem item) async {
    await ref
        .read(fieldRepositoryProvider)
        .saveBeat(
          plan.withItems(<BeatItem>[
            for (final i in plan.items)
              if (i != item) i,
          ]),
        );
  }

  Future<void> _addFarmer(BeatPlan plan) async {
    final farmers = await ref.read(farmerRepositoryProvider).farmers();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<FarmerSummary>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final f in farmers)
              ListTile(
                key: Key('beat-pick-farmer-${f.id}'),
                title: Text(f.name),
                subtitle: Text(f.villageName),
                onTap: () => Navigator.of(context).pop(f),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await ref
        .read(fieldRepositoryProvider)
        .saveBeat(
          plan.withItems(<BeatItem>[
            ...plan.items,
            BeatItem(
              id: '',
              kind: 'farmer',
              farmerId: chosen.id,
              farmerName: chosen.name,
              villageId: chosen.villageId,
              villageName: chosen.villageName,
              source: 'officer',
            ),
          ]),
        );
  }

  Future<void> _addVillage(BeatPlan plan) async {
    final villages = await ref.read(farmerRepositoryProvider).villages();
    if (!mounted || villages.isEmpty) return;
    final chosen = await showModalBottomSheet<Village>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final v in villages)
              ListTile(
                key: Key('beat-pick-village-${v.id}'),
                title: Text(v.name),
                onTap: () => Navigator.of(context).pop(v),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await ref
        .read(fieldRepositoryProvider)
        .saveBeat(
          plan.withItems(<BeatItem>[
            ...plan.items,
            BeatItem(
              id: '',
              kind: 'village',
              villageId: chosen.id,
              villageName: chosen.name,
              source: 'officer',
            ),
          ]),
        );
  }

  String _reasonLabel(CoreLocalizations l10n, BeatReasonCode code) =>
      switch (code) {
        BeatReasonCode.followUpDue => l10n.beatReasonFollowUp,
        BeatReasonCode.pestAlert => l10n.beatReasonPestAlert,
        BeatReasonCode.creditDue => l10n.beatReasonCreditDue,
        BeatReasonCode.demoPlotStage => l10n.beatReasonDemoStage,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final date = ref.watch(todayIstProvider);
    final plan = ref.watch(beatPlanProvider(date));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.beatTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('beat-map-toggle'),
            icon: Icon(_map ? Icons.list : Icons.map_outlined),
            tooltip: _map ? l10n.beatShowList : l10n.beatShowMap,
            onPressed: () => setState(() => _map = !_map),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: plan.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorState(
                  onRetry: () => ref.invalidate(beatPlanProvider(date)),
                ),
                data: (data) => data == null || data.isEmpty
                    ? EmptyState(
                        key: const Key('beat-empty'),
                        icon: Icons.map_outlined,
                        title: l10n.beatEmpty,
                        help: l10n.beatEmptyHelp,
                        actionLabel: data == null
                            ? null
                            : l10n.farmersAddFarmer,
                        onAction: data == null
                            ? null
                            : () => unawaited(_addFarmer(data)),
                      )
                    : _map
                    ? _BeatMap(plan: data)
                    : _BeatList(
                        plan: data,
                        reasonLabel: _reasonLabel,
                        onReorder: (o, n) => unawaited(_reorder(data, o, n)),
                        onRemove: (i) => unawaited(_remove(data, i)),
                        onAddFarmer: () => unawaited(_addFarmer(data)),
                        onAddVillage: () => unawaited(_addVillage(data)),
                      ),
              ),
            ),
          ],
        ),
      ),
      backgroundColor: p.background,
    );
  }
}

class _BeatList extends StatelessWidget {
  const _BeatList({
    required this.plan,
    required this.reasonLabel,
    required this.onReorder,
    required this.onRemove,
    required this.onAddFarmer,
    required this.onAddVillage,
  });

  final BeatPlan plan;
  final String Function(CoreLocalizations, BeatReasonCode) reasonLabel;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<BeatItem> onRemove;
  final VoidCallback onAddFarmer;
  final VoidCallback onAddVillage;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.spaceScreenPadding,
            Tokens.space3,
            Tokens.spaceScreenPadding,
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.beatTarget(plan.items.length, plan.target),
                  key: const Key('beat-target'),
                  style: app.text.label,
                ),
              ),
              if (plan.status == 'edited')
                FieldCaption(
                  l10n.fieldPendingSync,
                  icon: Icons.cloud_upload_outlined,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.spaceScreenPadding,
            vertical: Tokens.space1,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FieldCaption(l10n.beatReorderHint, icon: Icons.drag_handle),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.spaceScreenPadding,
            ),
            onReorderItem: onReorder,
            children: <Widget>[
              for (final (index, item) in plan.items.indexed)
                FieldCard(
                  key: Key('beat-item-${item.farmerId ?? item.villageId}'),
                  child: ListTile(
                    leading: ReorderableDragStartListener(
                      key: Key('beat-drag-${item.farmerId ?? item.villageId}'),
                      index: index,
                      child: Icon(
                        item.kind == 'village'
                            ? Icons.holiday_village_outlined
                            : Icons.person_outline,
                        color: p.primary,
                      ),
                    ),
                    title: Text(item.title, style: app.text.label),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (item.kind == 'village')
                          FieldCaption(l10n.beatVillageKind)
                        else if (item.villageName != null)
                          FieldCaption(item.villageName!),
                        if (item.reasons.isNotEmpty) ...<Widget>[
                          const SizedBox(height: Tokens.space1),
                          Wrap(
                            spacing: Tokens.space1,
                            runSpacing: Tokens.space1,
                            children: <Widget>[
                              for (final r in item.reasons)
                                _ReasonChip(
                                  label: reasonLabel(l10n, r),
                                  code: r,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (item.farmerId != null)
                          IconButton(
                            key: Key('beat-start-visit-${item.farmerId}'),
                            icon: const Icon(Icons.place_outlined),
                            tooltip: l10n.actionStartVisit,
                            onPressed: () => context.push(
                              VisitRoutes.start(farmerId: item.farmerId),
                            ),
                          ),
                        IconButton(
                          key: Key(
                            'beat-remove-${item.farmerId ?? item.villageId}',
                          ),
                          icon: const Icon(Icons.close),
                          tooltip: l10n.beatRemove,
                          onPressed: () => onRemove(item),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  key: const Key('beat-add-farmer'),
                  label: l10n.farmersAddFarmer,
                  icon: Icons.person_add_alt_1_outlined,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  onPressed: onAddFarmer,
                ),
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: AppButton(
                  key: const Key('beat-add-village'),
                  label: l10n.beatAddVillage,
                  icon: Icons.holiday_village_outlined,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  onPressed: onAddVillage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.label, required this.code});

  final String label;
  final BeatReasonCode code;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final color = switch (code) {
      BeatReasonCode.pestAlert => p.statusDanger,
      BeatReasonCode.creditDue => p.statusWarning,
      BeatReasonCode.demoPlotStage => p.statusInfo,
      BeatReasonCode.followUpDue => p.primary,
    };
    return Container(
      key: Key('beat-reason-${code.wire}'),
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space1,
      ),
      decoration: BoxDecoration(
        color: app.tint(color),
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
        border: Border.all(color: color, width: app.borderWidth),
      ),
      child: Text(label, style: app.text.caption.copyWith(color: p.text)),
    );
  }
}

class _BeatMap extends ConsumerWidget {
  const _BeatMap({required this.plan});

  final BeatPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final villages = ref.watch(villagesProvider).value ?? const <Village>[];
    final byId = <String, Village>{for (final v in villages) v.id: v};
    final points = <GeoPoint>[
      for (final item in plan.items)
        if (byId[item.villageId] case final Village v)
          if (v.latitude != null && v.longitude != null)
            GeoPoint(v.latitude!, v.longitude!),
    ];
    if (points.isEmpty) {
      return EmptyState(
        key: const Key('beat-map-empty'),
        icon: Icons.map_outlined,
        title: l10n.beatShowMap,
        help: l10n.beatEmptyHelp,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      child: MapPanel(
        key: const Key('beat-map'),
        boundary: points,
        closed: false,
        interactive: false,
        tileProvider: ref.watch(mapTileProviderProvider),
        height: 400,
      ),
    );
  }
}
