import 'dart:async';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'field_widgets.dart';

/// Localised label for a demo stage.
String demoStageLabel(CoreLocalizations l10n, DemoStage stage) =>
    switch (stage) {
      DemoStage.sown => l10n.demoStageSown,
      DemoStage.vegetative => l10n.demoStageVegetative,
      DemoStage.flowering => l10n.demoStageFlowering,
      DemoStage.fruiting => l10n.demoStageFruiting,
      DemoStage.maturity => l10n.demoStageMaturity,
      DemoStage.harvest => l10n.demoStageHarvest,
    };

/// Localised label for a demo plot status.
String demoStatusLabel(CoreLocalizations l10n, DemoStatus status) =>
    switch (status) {
      DemoStatus.created => l10n.demoStatusCreated,
      DemoStatus.active => l10n.demoStatusActive,
      DemoStatus.harvested => l10n.demoStatusHarvested,
      DemoStatus.reported => l10n.demoStatusReported,
    };

/// A36 Demo plots (FA-026), list half.
class DemoPlotsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const DemoPlotsScreen({super.key});

  @override
  ConsumerState<DemoPlotsScreen> createState() => _DemoPlotsScreenState();
}

class _DemoPlotsScreenState extends ConsumerState<DemoPlotsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(fieldRepositoryProvider).refreshDemoPlots());
  }

  Future<void> _create() async {
    final farmers = await ref.read(farmerRepositoryProvider).farmers();
    if (!mounted) return;
    final result = await showModalBottomSheet<NewDemoResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => NewDemoPlotSheet(farmers: farmers),
    );
    if (result == null || !mounted) return;
    final plot = await ref
        .read(fieldRepositoryProvider)
        .createDemoPlot(
          farmerId: result.farmerId,
          farmerName: result.farmerName,
          cropPlotId: result.cropPlotId,
          treatment: result.treatment,
          baseline: result.baseline,
        );
    if (!mounted) return;
    unawaited(context.push(AppRoutes.demoPlotPath(plot.id)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final plots = ref.watch(demoPlotsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.demoTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('demo-new'),
        onPressed: () => unawaited(_create()),
        icon: const Icon(Icons.science_outlined),
        label: Text(l10n.demoNew),
      ),
      body: SafeArea(
        child: plots.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(demoPlotsProvider)),
          data: (rows) => rows.isEmpty
              ? EmptyState(
                  key: const Key('demo-empty'),
                  icon: Icons.science_outlined,
                  title: l10n.demoEmpty,
                  help: l10n.demoEmptyHelp,
                )
              : ListView(
                  padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                  children: <Widget>[
                    for (final p in rows)
                      FieldCard(
                        key: Key('demo-${p.id}'),
                        onTap: () => context.push(AppRoutes.demoPlotPath(p.id)),
                        child: ListTile(
                          leading: const Icon(Icons.science_outlined),
                          title: Text(p.treatment, style: app.text.label),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              FieldCaption(p.farmerName ?? p.farmerId),
                              FieldCaption(demoStatusLabel(l10n, p.status)),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// What the "new demo plot" sheet hands back.
class NewDemoResult {
  /// Creates the result.
  const NewDemoResult({
    required this.farmerId,
    required this.cropPlotId,
    required this.treatment,
    required this.baseline,
    this.farmerName,
  });

  /// Farmer.
  final String farmerId;

  /// Crop plot under demo.
  final String cropPlotId;

  /// Product or practice being demonstrated.
  final String treatment;

  /// `farmer_practice` or `comparison_plot`.
  final String baseline;

  /// Farmer name for display.
  final String? farmerName;
}

/// Farmer + crop plot + treatment + baseline.
class NewDemoPlotSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const NewDemoPlotSheet({required this.farmers, super.key});

  /// Farmers to choose from.
  final List<FarmerSummary> farmers;

  @override
  ConsumerState<NewDemoPlotSheet> createState() => _NewDemoPlotSheetState();
}

class _NewDemoPlotSheetState extends ConsumerState<NewDemoPlotSheet> {
  final TextEditingController _treatment = TextEditingController();
  FarmerSummary? _farmer;
  String? _cropPlotId;
  String _baseline = 'farmer_practice';

  @override
  void initState() {
    super.initState();
    _farmer = widget.farmers.firstOrNull;
  }

  @override
  void dispose() {
    _treatment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final farmer = _farmer;
    final detail = farmer == null
        ? null
        : ref.watch(farmerDetailProvider(farmer.id)).value;
    final plots = <(String id, String label)>[
      if (detail != null)
        for (final farm in detail.farms)
          for (final plot in farm.plots)
            (plot.id, plot.variety ?? plot.cropId ?? plot.id),
    ];
    if (_cropPlotId == null && plots.isNotEmpty) _cropPlotId = plots.first.$1;
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.spaceScreenPadding,
        right: Tokens.spaceScreenPadding,
        top: Tokens.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.demoNew, style: app.text.heading),
            const SizedBox(height: Tokens.space3),
            Wrap(
              spacing: Tokens.space2,
              children: <Widget>[
                for (final f in widget.farmers)
                  ChoiceChip(
                    key: Key('demo-farmer-${f.id}'),
                    label: Text(f.name),
                    selected: _farmer?.id == f.id,
                    onSelected: (_) => setState(() {
                      _farmer = f;
                      _cropPlotId = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space3),
            if (plots.isNotEmpty)
              Wrap(
                spacing: Tokens.space2,
                children: <Widget>[
                  for (final (id, label) in plots)
                    ChoiceChip(
                      key: Key('demo-plot-$id'),
                      label: Text(label),
                      selected: _cropPlotId == id,
                      onSelected: (_) => setState(() => _cropPlotId = id),
                    ),
                ],
              ),
            const SizedBox(height: Tokens.space3),
            VoiceTextField(
              label: l10n.demoTreatment,
              controller: _treatment,
              onChanged: (_) => setState(() {}),
              fieldKey: const Key('demo-treatment'),
              micKey: const Key('demo-treatment-mic'),
            ),
            const SizedBox(height: Tokens.space3),
            Text(
              l10n.demoBaseline,
              style: app.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: Tokens.space2),
            Wrap(
              spacing: Tokens.space2,
              children: <Widget>[
                for (final (value, label) in <(String, String)>[
                  ('farmer_practice', l10n.demoBaselinePractice),
                  ('comparison_plot', l10n.demoBaselineComparison),
                ])
                  ChoiceChip(
                    key: Key('demo-baseline-$value'),
                    label: Text(label),
                    selected: _baseline == value,
                    onSelected: (_) => setState(() => _baseline = value),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space4),
            AppButton(
              key: const Key('demo-create'),
              label: l10n.demoNew,
              onPressed:
                  farmer == null ||
                      _cropPlotId == null ||
                      _treatment.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      NewDemoResult(
                        farmerId: farmer.id,
                        farmerName: farmer.name,
                        cropPlotId: _cropPlotId!,
                        treatment: _treatment.text.trim(),
                        baseline: _baseline,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A36 Demo plot detail: stage photos and observations, the comparison
/// with farmer practice, the yield entry and the status lifecycle
/// (`created → active → harvested → reported`).
class DemoPlotScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const DemoPlotScreen({required this.demoPlotId, super.key});

  /// Demo plot being shown.
  final String demoPlotId;

  @override
  ConsumerState<DemoPlotScreen> createState() => _DemoPlotScreenState();
}

class _DemoPlotScreenState extends ConsumerState<DemoPlotScreen> {
  Future<void> _addObservation(DemoPlot plot) async {
    final result = await showModalBottomSheet<ObservationResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const AddObservationSheet(),
    );
    if (result == null || !mounted) return;
    final photos = <(String, Uint8List)>[];
    final store = ref.read(photoStoreProvider);
    for (final (i, bytes) in result.photos.indexed) {
      photos.add((
        await store.save('demo-${plot.id}-${result.stage.name}-$i.jpg', bytes),
        bytes,
      ));
    }
    await ref
        .read(fieldRepositoryProvider)
        .addObservation(
          demoPlotId: plot.id,
          stage: result.stage,
          side: result.side,
          note: result.note,
          photos: photos,
        );
  }

  Future<void> _enterYield(DemoPlot plot) async {
    final result = await showModalBottomSheet<(double, double?)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const YieldSheet(),
    );
    if (result == null || !mounted) return;
    await ref
        .read(fieldRepositoryProvider)
        .enterYield(
          plot.id,
          demoKgPerAcre: result.$1,
          practiceKgPerAcre: result.$2,
        );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final plot = ref.watch(demoPlotProvider(widget.demoPlotId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.demoTitle)),
      body: SafeArea(
        child: plot.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const ErrorState(),
          data: (d) => d == null
              ? EmptyState(
                  key: const Key('demo-missing'),
                  icon: Icons.science_outlined,
                  title: l10n.demoEmpty,
                  help: l10n.demoEmptyHelp,
                )
              : ListView(
                  padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                  children: <Widget>[
                    Text(d.treatment, style: app.text.heading),
                    FieldCaption(d.farmerName ?? d.farmerId),
                    const SizedBox(height: Tokens.space1),
                    FieldCaption(
                      demoStatusLabel(l10n, d.status),
                      key: const Key('demo-status'),
                      icon: Icons.timeline_outlined,
                    ),
                    if (d.pending)
                      Padding(
                        padding: const EdgeInsets.only(top: Tokens.space1),
                        child: FieldCaption(
                          l10n.fieldPendingSync,
                          icon: Icons.cloud_upload_outlined,
                        ),
                      ),
                    const SizedBox(height: Tokens.space3),
                    if (d.demoYieldKgPerAcre != null)
                      FieldCard(
                        key: const Key('demo-comparison'),
                        color: app.tint(p.statusSuccessContainer),
                        child: Padding(
                          padding: const EdgeInsets.all(Tokens.space3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(l10n.demoComparison, style: app.text.label),
                              const SizedBox(height: Tokens.space1),
                              Text(
                                '${d.demoYieldKgPerAcre!.toStringAsFixed(0)}'
                                ' · '
                                '${d.practiceYieldKgPerAcre?.toStringAsFixed(0) ?? '—'}',
                                style: app.text.body,
                              ),
                              if (d.gainPct != null)
                                Text(
                                  l10n.demoYieldGain(
                                    d.gainPct!.toStringAsFixed(0),
                                  ),
                                  key: const Key('demo-gain'),
                                  style: app.text.label.copyWith(
                                    color: p.statusSuccess,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Text(l10n.demoAddObservation, style: app.text.heading),
                    const SizedBox(height: Tokens.space2),
                    for (final o in d.observations)
                      FieldCard(
                        key: Key('demo-observation-${o.id}'),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.photo_camera_outlined),
                          title: Text(
                            demoStageLabel(l10n, o.stage),
                            style: app.text.label,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (o.note != null && o.note!.isNotEmpty)
                                Text(o.note!, style: app.text.body),
                              FieldCaption(
                                o.pending
                                    ? l10n.fieldPendingSync
                                    : formatDateIst(o.observedAt),
                              ),
                            ],
                          ),
                          trailing: Text(
                            '${o.photoUris.length}',
                            style: app.text.caption,
                          ),
                        ),
                      ),
                    const SizedBox(height: Tokens.space2),
                    AppButton(
                      key: const Key('demo-add-observation'),
                      label: l10n.demoAddObservation,
                      icon: Icons.add_a_photo_outlined,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      onPressed: d.status == DemoStatus.reported
                          ? null
                          : () => unawaited(_addObservation(d)),
                    ),
                    const SizedBox(height: Tokens.space3),
                    for (final next in d.nextStates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Tokens.space2),
                        child: AppButton(
                          key: Key('demo-transition-${next.name}'),
                          label: next == DemoStatus.active
                              ? l10n.demoStart
                              : l10n.demoReport,
                          variant: AppButtonVariant.secondary,
                          size: AppButtonSize.medium,
                          onPressed: () => unawaited(
                            ref
                                .read(fieldRepositoryProvider)
                                .transitionDemoPlot(d.id, next),
                          ),
                        ),
                      ),
                    if (d.status == DemoStatus.active)
                      AppButton(
                        key: const Key('demo-enter-yield'),
                        label: l10n.demoEnterYield,
                        onPressed: () => unawaited(_enterYield(d)),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// What the observation sheet hands back.
class ObservationResult {
  /// Creates the result.
  const ObservationResult({
    required this.stage,
    required this.side,
    this.note,
    this.photos = const <Uint8List>[],
  });

  /// Crop stage.
  final DemoStage stage;

  /// `demo` | `practice` | `both`.
  final String side;

  /// Officer's note.
  final String? note;

  /// Processed stage photos (NF-004).
  final List<Uint8List> photos;
}

/// Stage + side + photos + note.
class AddObservationSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const AddObservationSheet({super.key});

  @override
  ConsumerState<AddObservationSheet> createState() =>
      _AddObservationSheetState();
}

class _AddObservationSheetState extends ConsumerState<AddObservationSheet> {
  final TextEditingController _note = TextEditingController();
  final List<Uint8List> _photos = <Uint8List>[];
  DemoStage _stage = DemoStage.vegetative;
  String _side = 'demo';
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() => _busy = true);
    final pending = await ref.read(receiptCaptureProvider)();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (pending != null) _photos.add(pending.bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.spaceScreenPadding,
        right: Tokens.spaceScreenPadding,
        top: Tokens.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.demoAddObservation, style: app.text.heading),
            const SizedBox(height: Tokens.space3),
            Wrap(
              spacing: Tokens.space2,
              runSpacing: Tokens.space2,
              children: <Widget>[
                for (final s in DemoStage.values)
                  ChoiceChip(
                    key: Key('demo-stage-${s.name}'),
                    label: Text(demoStageLabel(l10n, s)),
                    selected: _stage == s,
                    onSelected: (_) => setState(() => _stage = s),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space3),
            Text(
              l10n.demoSide,
              style: app.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: Tokens.space2),
            Wrap(
              spacing: Tokens.space2,
              children: <Widget>[
                for (final (value, label) in <(String, String)>[
                  ('demo', l10n.demoSideDemo),
                  ('practice', l10n.demoBaselinePractice),
                  ('both', l10n.demoSideBoth),
                ])
                  ChoiceChip(
                    key: Key('demo-side-$value'),
                    label: Text(label),
                    selected: _side == value,
                    onSelected: (_) => setState(() => _side = value),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space3),
            AppButton(
              key: const Key('demo-take-photo'),
              label: l10n.demoTakePhoto,
              icon: Icons.photo_camera_outlined,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              loading: _busy,
              onPressed: () => unawaited(_capture()),
            ),
            if (_photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Tokens.space2),
                child: FieldCaption(
                  '${_photos.length}',
                  key: const Key('demo-photo-count'),
                  icon: Icons.check_circle_outline,
                  color: p.statusSuccess,
                ),
              ),
            const SizedBox(height: Tokens.space3),
            VoiceTextField(
              label: l10n.demoObservationNote,
              controller: _note,
              maxLines: 3,
              fieldKey: const Key('demo-note'),
              micKey: const Key('demo-note-mic'),
            ),
            const SizedBox(height: Tokens.space4),
            AppButton(
              key: const Key('demo-observation-save'),
              label: l10n.actionDone,
              onPressed: () => Navigator.of(context).pop(
                ObservationResult(
                  stage: _stage,
                  side: _side,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  photos: _photos,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Demo and farmer-practice yields in kg per acre.
class YieldSheet extends StatefulWidget {
  /// Creates the sheet.
  const YieldSheet({super.key});

  @override
  State<YieldSheet> createState() => _YieldSheetState();
}

class _YieldSheetState extends State<YieldSheet> {
  final TextEditingController _demo = TextEditingController();
  final TextEditingController _practice = TextEditingController();

  @override
  void dispose() {
    _demo.dispose();
    _practice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final demo = double.tryParse(_demo.text.trim());
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.spaceScreenPadding,
        right: Tokens.spaceScreenPadding,
        top: Tokens.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.demoEnterYield, style: app.text.heading),
          const SizedBox(height: Tokens.space3),
          AppTextField(
            key: const Key('demo-yield-demo'),
            label: l10n.demoYieldDemo,
            controller: _demo,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Tokens.space3),
          AppTextField(
            key: const Key('demo-yield-practice'),
            label: l10n.demoYieldPractice,
            controller: _practice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: Tokens.space4),
          AppButton(
            key: const Key('demo-yield-save'),
            label: l10n.actionDone,
            onPressed: demo == null || demo <= 0
                ? null
                : () =>
                      Navigator.of(context)
                          .pop((demo, double.tryParse(_practice.text.trim()))),
          ),
        ],
      ),
    );
  }
}
