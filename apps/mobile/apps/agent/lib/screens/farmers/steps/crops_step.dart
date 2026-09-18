import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wizard_copy.dart';

/// A21c: repeatable crop plot rows for the current farm (crop tile,
/// variety, sowing date DD-MM-YYYY with the season derived, optional area)
/// and the "add another farm" entry point (FA-013).
class CropsStep extends ConsumerWidget {
  /// Creates the step.
  const CropsStep({
    this.showIssues = false,
    this.allowAddFarm = true,
    super.key,
  });

  /// Show validation errors (after a failed Next).
  final bool showIssues;

  /// Offer "Add another farm" (not on A23).
  final bool allowAddFarm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(registrationProvider);
    final wizard = ref.read(registrationProvider.notifier);
    final draft = state.draft!;
    final farm = draft.farm!;
    final crops = ref.watch(cropsProvider).value ?? CropRef.pilotFallback;
    final issues = showIssues
        ? wizard.issuesFor(RegistrationStep.crops)
        : const <StepIssue>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (draft.farms.length > 1) ...<Widget>[
          Wrap(
            spacing: Tokens.space2,
            children: <Widget>[
              for (var i = 0; i < draft.farms.length; i++)
                CropChip(
                  key: Key('reg-farm-tab-$i'),
                  data: CropChipData(
                    name: draft.farms[i].name.isEmpty
                        ? l10n.regFarmIndex(i + 1)
                        : draft.farms[i].name,
                    icon: Icons.grass_outlined,
                  ),
                  selected: i == draft.currentFarm,
                  onTap: () => unawaited(wizard.selectFarm(i)),
                ),
            ],
          ),
          const SizedBox(height: Tokens.space3),
        ],
        Text(
          l10n.regCropsHelp,
          style: app.text.body.copyWith(color: p.textSecondary),
        ),
        if (issues.isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          NoticeBox(
            text: issues.map((i) => issueText(l10n, i)).join('\n'),
            icon: Icons.error_outline,
            color: p.statusDanger,
            container: p.statusDangerContainer,
          ),
        ],
        for (final (i, plot) in farm.plots.indexed) ...<Widget>[
          const SizedBox(height: Tokens.space3),
          _PlotCard(index: i, plot: plot, crops: crops),
        ],
        const SizedBox(height: Tokens.space3),
        AppButton(
          key: const Key('reg-add-crop'),
          label: l10n.regAddCrop,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.medium,
          icon: Icons.add,
          onPressed: () => unawaited(wizard.addPlot()),
        ),
        if (allowAddFarm) ...<Widget>[
          const SizedBox(height: Tokens.space4),
          Text(
            l10n.regFarmsCount(draft.farms.length),
            style: app.text.label.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: Tokens.space2),
          AppButton(
            key: const Key('reg-add-farm'),
            label: l10n.regAddFarm,
            variant: AppButtonVariant.tertiary,
            size: AppButtonSize.medium,
            icon: Icons.add_location_alt_outlined,
            onPressed: wizard.issuesFor(RegistrationStep.crops).isEmpty
                ? () => unawaited(wizard.addFarm())
                : null,
          ),
        ],
      ],
    );
  }
}

class _PlotCard extends ConsumerWidget {
  const _PlotCard({
    required this.index,
    required this.plot,
    required this.crops,
  });

  final int index;
  final CropPlotDraft plot;
  final List<CropRef> crops;

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: plot.sowingDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    await ref
        .read(registrationProvider.notifier)
        .updatePlot(
          plot.id,
          sowingDate: DateTime(picked.year, picked.month, picked.day),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final wizard = ref.read(registrationProvider.notifier);
    final date = plot.sowingDate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.regPlotTitle(index + 1),
                    style: app.text.heading,
                  ),
                ),
                AppButton(
                  key: Key('reg-remove-crop-$index'),
                  label: l10n.regRemoveCrop,
                  variant: AppButtonVariant.tertiary,
                  size: AppButtonSize.medium,
                  expand: false,
                  icon: Icons.delete_outline,
                  onPressed: () => unawaited(wizard.removePlot(plot.id)),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space2),
            Text(
              l10n.regCropLabel,
              style: app.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: Tokens.space2),
            Wrap(
              spacing: Tokens.space2,
              runSpacing: Tokens.space2,
              children: <Widget>[
                for (final crop in crops)
                  CropChip(
                    key: Key('reg-crop-$index-${crop.code}'),
                    data: CropChipData(name: cropName(context, crop)),
                    selected: crop.id == plot.cropId,
                    onTap: () =>
                        unawaited(wizard.updatePlot(plot.id, cropId: crop.id)),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.space3),
            DraftTextField(
              fieldKey: Key('reg-variety-$index'),
              label: l10n.regVarietyLabel,
              value: plot.variety,
              hintText: l10n.regVarietyHint,
              onChanged: (v) =>
                  unawaited(wizard.updatePlot(plot.id, variety: v)),
            ),
            const SizedBox(height: Tokens.space3),
            Text(
              l10n.regSowingDateLabel,
              style: app.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: Tokens.space2),
            Semantics(
              button: true,
              label:
                  '${l10n.regSowingDateLabel}: '
                  '${date == null ? l10n.regSowingDateHint : formatDateDdMmYyyy(date)}',
              excludeSemantics: true,
              child: Material(
                color: p.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusInput),
                  side: app.borderSide,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Key('reg-sowing-$index'),
                  onTap: () => unawaited(_pickDate(context, ref)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space4,
                      vertical: Tokens.space3,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.event_outlined, color: p.textSecondary),
                        const SizedBox(width: Tokens.space2),
                        Expanded(
                          child: Text(
                            date == null
                                ? l10n.regSowingDateHint
                                : formatDateDdMmYyyy(date),
                            style: app.text.body.copyWith(
                              color: date == null ? p.textMuted : p.text,
                            ),
                          ),
                        ),
                        if (date != null)
                          Text(
                            l10n.regSeasonAuto(
                              Seasons.label(l10n, Seasons.forDate(date)),
                            ),
                            style: app.text.caption.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Tokens.space3),
            DraftTextField(
              fieldKey: Key('reg-plot-area-$index'),
              label: l10n.regPlotAreaLabel,
              value: plot.areaAcres == null ? '' : plot.areaAcres.toString(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v.replaceAll(',', '.'));
                unawaited(
                  wizard.updatePlot(
                    plot.id,
                    areaAcres: parsed,
                    clearArea: parsed == null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
