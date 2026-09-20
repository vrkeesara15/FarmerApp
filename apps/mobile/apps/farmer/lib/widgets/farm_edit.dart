import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kisan_widgets.dart';

/// One choice of [showChoiceSheet].
typedef SheetChoice = ({String value, IconData icon, String label});

/// Bottom sheet of big icon tiles; returns the tapped value (tap-only
/// editing, NF-010).
Future<String?> showChoiceSheet(
  BuildContext context, {
  required String title,
  required List<SheetChoice> choices,
  String? selected,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    final app = context.app;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, style: app.text.heading),
            const SizedBox(height: Tokens.space3),
            ChoiceGrid(
              children: <Widget>[
                for (final c in choices)
                  ChoiceTile(
                    key: Key('choice-${c.value}'),
                    icon: c.icon,
                    label: c.label,
                    selected: c.value == selected,
                    onTap: () => Navigator.of(context).pop(c.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  },
);

/// A farm with its map thumbnail, irrigation, soil and crops; in
/// [editable] mode every value opens a tile sheet and saves online
/// (FM-003 "confirm or edit simple fields").
class FarmSummaryCard extends ConsumerWidget {
  /// Creates the card.
  const FarmSummaryCard({
    required this.farm,
    this.editable = false,
    this.calendar,
    this.onOpenCalendar,
    super.key,
  });

  /// The farm.
  final KisanFarm farm;

  /// Values are tappable.
  final bool editable;

  /// The synced crop calendar, for "next task" per plot (FM-007).
  final CropCalendar? calendar;

  /// Opens F42 for a crop plot.
  final void Function(String cropPlotId)? onOpenCalendar;

  Future<void> _report(BuildContext context, KisanWrite result) async {
    final l10n = CoreLocalizations.of(context);
    showKisanMessage(context, switch (result) {
      KisanWrite.done || KisanWrite.queued => l10n.kisanSaved,
      KisanWrite.offline => l10n.kisanNeedsInternet,
      KisanWrite.refused => l10n.kisanSaveFailed,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final crops = ref.watch(cropsProvider).value ?? const <CropRef>[];
    final repo = ref.read(kisanRepositoryProvider);
    return Card(
      key: Key('farm-${farm.id}'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (farm.boundary.length >= 3)
            MapPanel(
              boundary: farm.boundary,
              interactive: false,
              showCorners: false,
              height: 120,
              tileProvider: ref.watch(mapTileProviderProvider),
              userAgentPackageName: 'in.farmerapp.kisan',
            )
          else
            Container(
              height: 72,
              color: app.tint(p.primaryContainer),
              alignment: Alignment.center,
              child: Icon(Icons.landscape_outlined, color: p.primary, size: 40),
            ),
          Padding(
            padding: const EdgeInsets.all(Tokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  farm.name?.isNotEmpty == true
                      ? farm.name!
                      : l10n.kisanFarmUnnamed,
                  style: app.text.heading,
                ),
                if (farm.areaAcres != null)
                  Text(
                    l10n.kisanAcres(_acres(farm.areaAcres!)),
                    style: app.text.body.copyWith(color: p.textSecondary),
                  ),
                const SizedBox(height: Tokens.space2),
                Wrap(
                  spacing: Tokens.space2,
                  runSpacing: Tokens.space2,
                  children: <Widget>[
                    _ValueChip(
                      key: Key('farm-irrigation-${farm.id}'),
                      icon: irrigationIcon(farm.irrigation),
                      label: farm.irrigation == null
                          ? l10n.kisanIrrigationUnknown
                          : IrrigationTypes.label(l10n, farm.irrigation!),
                      editable: editable,
                      onTap: () async {
                        final v = await showChoiceSheet(
                          context,
                          title: l10n.kisanIrrigationQuestion,
                          selected: farm.irrigation,
                          choices: <SheetChoice>[
                            for (final i in IrrigationTypes.values)
                              (
                                value: i,
                                icon: irrigationIcon(i),
                                label: IrrigationTypes.label(l10n, i),
                              ),
                          ],
                        );
                        if (v == null || v == farm.irrigation) return;
                        final r = await repo.setFarmDetails(
                          farm,
                          irrigation: v,
                        );
                        if (context.mounted) await _report(context, r);
                      },
                    ),
                    _ValueChip(
                      key: Key('farm-soil-${farm.id}'),
                      icon: soilIcon(farm.soil),
                      label: farm.soil == null
                          ? l10n.kisanSoilUnknown
                          : SoilTypes.label(l10n, farm.soil!),
                      editable: editable,
                      onTap: () async {
                        final v = await showChoiceSheet(
                          context,
                          title: l10n.kisanSoilQuestion,
                          selected: farm.soil,
                          choices: <SheetChoice>[
                            for (final s in SoilTypes.values)
                              (
                                value: s,
                                icon: soilIcon(s),
                                label: SoilTypes.label(l10n, s),
                              ),
                          ],
                        );
                        if (v == null || v == farm.soil) return;
                        final r = await repo.setFarmDetails(farm, soil: v);
                        if (context.mounted) await _report(context, r);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.space2),
                for (final plot in farm.plots)
                  ListTile(
                    key: Key('plot-${plot.id}'),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: Tokens.sizeTouchTargetMin,
                    leading: Icon(stageIcon(plot.stage), color: p.primary),
                    title: Text(
                      cropName(context, crops, plot.cropId),
                      style: app.text.label,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          plot.stage == null
                              ? l10n.kisanStageUnknown
                              : CropStages.label(l10n, plot.stage!),
                        ),
                        _NextTask(
                          plot: plot,
                          calendar: calendar,
                          onOpen: onOpenCalendar,
                        ),
                      ],
                    ),
                    trailing: editable
                        ? Icon(Icons.edit_outlined, color: p.primary)
                        : null,
                    onTap: !editable
                        ? null
                        : () async {
                            final v = await showChoiceSheet(
                              context,
                              title: l10n.kisanStageQuestion,
                              selected: plot.stage,
                              choices: <SheetChoice>[
                                for (final s in CropStages.values)
                                  (
                                    value: s,
                                    icon: stageIcon(s),
                                    label: CropStages.label(l10n, s),
                                  ),
                              ],
                            );
                            if (v == null || v == plot.stage) return;
                            final r = await repo.setPlotStage(plot, v);
                            if (context.mounted) await _report(context, r);
                          },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _acres(double a) =>
      a == a.roundToDouble() ? a.toStringAsFixed(0) : a.toStringAsFixed(1);
}

/// FM-007: the plot's next task with a link to F42, or nothing when the
/// calendar has not been synced yet.
class _NextTask extends StatelessWidget {
  const _NextTask({
    required this.plot,
    required this.calendar,
    required this.onOpen,
  });

  final KisanCropPlot plot;
  final CropCalendar? calendar;
  final void Function(String cropPlotId)? onOpen;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final plotCalendar = calendar?.plot(plot.id);
    if (plotCalendar == null) {
      return Text(
        l10n.kisanNextTaskSoon,
        style: app.text.caption.copyWith(color: app.palette.textSecondary),
      );
    }
    final next = plotCalendar.nextTask(calendar!.today);
    final label = next == null
        ? l10n.calendarAllDone
        : l10n.calendarNextTask(next.titleIn(lang) ?? next.taskKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          key: Key('plot-next-${plot.id}'),
          style: app.text.caption.copyWith(color: app.palette.textSecondary),
        ),
        if (onOpen != null)
          TextButton.icon(
            key: Key('plot-calendar-${plot.id}'),
            onPressed: () => onOpen!(plot.id),
            icon: const Icon(Icons.event_note_outlined),
            label: Text(l10n.kisanCropCalendar),
            style: TextButton.styleFrom(
              minimumSize: const Size(
                Tokens.sizeTouchTargetMin,
                Tokens.sizeTouchTargetMin,
              ),
            ),
          ),
      ],
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({
    required this.icon,
    required this.label,
    required this.editable,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool editable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final avatar = Icon(
      icon,
      size: Tokens.space4 + 2,
      color: app.palette.primary,
    );
    if (!editable) {
      return Chip(
        avatar: avatar,
        label: Text(label, style: app.text.label),
      );
    }
    return ActionChip(
      avatar: avatar,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: app.text.label),
          const SizedBox(width: Tokens.space1),
          Icon(
            Icons.edit_outlined,
            size: Tokens.space4,
            color: app.palette.primary,
          ),
        ],
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      onPressed: onTap,
    );
  }
}
