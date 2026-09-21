import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/kisan_widgets.dart';

/// F41 Add a crop (FM-007): big crop tiles, a sowing-date calendar and
/// icon tiles for water and soil. Nothing is typed (NF-010) — the variety
/// is left out on purpose, because there is no tap-only variety list yet
/// (noted in docs/prs/M7-farmer-mobile.md).
///
/// Saving adds the crop plot to the farm and pulls the calendar again, so
/// the tasks for the new crop appear on F42 straight away.
class AddCropScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AddCropScreen({super.key});

  @override
  ConsumerState<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends ConsumerState<AddCropScreen> {
  String? _cropId;
  String? _farmId;
  DateTime? _sowingDate;
  String? _irrigation;
  String? _soil;
  bool _saving = false;

  DateTime get _today => ref.read(clockProvider)().toUtc();

  Future<void> _save(List<KisanFarm> farms) async {
    final cropId = _cropId;
    final farmId = _farmId ?? (farms.isEmpty ? null : farms.first.id);
    final sowing = _sowingDate;
    if (cropId == null || farmId == null || sowing == null) return;
    setState(() => _saving = true);
    final repo = ref.read(kisanRepositoryProvider);
    final result = await repo.addCrop(
      farmId: farmId,
      cropId: cropId,
      sowingDate: sowing,
      irrigation: _irrigation,
      soil: _soil,
    );
    if (result == KisanWrite.done) {
      await ref.read(advisoryRepositoryProvider).refreshCalendar();
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final l10n = CoreLocalizations.of(context);
    showKisanMessage(context, switch (result) {
      KisanWrite.done => l10n.addCropSaved,
      KisanWrite.queued => l10n.calendarSavedOffline,
      KisanWrite.offline => l10n.kisanNeedsInternet,
      KisanWrite.refused => l10n.kisanSaveFailed,
    });
    if (result == KisanWrite.done || result == KisanWrite.queued) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final crops = ref.watch(cropsProvider).value ?? CropRef.pilotFallback;
    final profile = ref.watch(kisanProfileProvider).value;
    final farms = profile?.value.farms ?? const <KisanFarm>[];
    final lang = Localizations.localeOf(context).languageCode;
    final ready = _cropId != null && _sowingDate != null && farms.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addCropTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: farms.isEmpty
                  ? EmptyState(
                      icon: Icons.landscape_outlined,
                      title: l10n.addCropNoFarm,
                      help: l10n.kisanNoCropsHelp,
                    )
                  : ListView(
                      // NF-009: the side padding is applied per item, not to
                      // the list, so the calendar below can use the full
                      // width. Material sizes a day cell at width / 7: inside
                      // 16 dp of padding that is 43 dp, under the 48 dp
                      // minimum; full-bleed it is 49 dp.
                      padding: const EdgeInsets.symmetric(
                        vertical: Tokens.spaceScreenPadding,
                      ),
                      children: <Widget>[
                        _Padded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              SpokenText(
                                promptId: 'f41_help',
                                text: l10n.addCropHelp,
                              ),
                              const SizedBox(height: Tokens.space3),
                              Text(
                                l10n.addCropWhichCrop,
                                style: app.text.heading,
                              ),
                              const SizedBox(height: Tokens.space2),
                              ChoiceGrid(
                                children: <Widget>[
                                  for (final crop in crops)
                                    ChoiceTile(
                                      key: Key('add-crop-${crop.code}'),
                                      icon: Icons.grass,
                                      label: crop.nameIn(lang),
                                      selected: crop.id == _cropId,
                                      onTap: () =>
                                          setState(() => _cropId = crop.id),
                                    ),
                                ],
                              ),
                              if (farms.length > 1) ...<Widget>[
                                const SizedBox(height: Tokens.space4),
                                Text(
                                  l10n.addCropWhichFarm,
                                  style: app.text.heading,
                                ),
                                const SizedBox(height: Tokens.space2),
                                ChoiceGrid(
                                  columns: 2,
                                  children: <Widget>[
                                    for (final farm in farms)
                                      ChoiceTile(
                                        key: Key('add-farm-${farm.id}'),
                                        icon: Icons.landscape_outlined,
                                        label: farm.name?.isNotEmpty == true
                                            ? farm.name!
                                            : l10n.kisanFarmUnnamed,
                                        selected:
                                            farm.id ==
                                            (_farmId ?? farms.first.id),
                                        onTap: () =>
                                            setState(() => _farmId = farm.id),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: Tokens.space4),
                              Text(
                                l10n.addCropWhenSown,
                                style: app.text.heading,
                              ),
                              if (_sowingDate != null)
                                Text(
                                  l10n.addCropSownOn(
                                    formatDateIst(_sowingDate!),
                                  ),
                                  key: const Key('add-crop-sown-on'),
                                  style: app.text.body,
                                ),
                            ],
                          ),
                        ),
                        // A calendar, not a text field: NF-010 allows no
                        // typing outside the phone number and the OTP. It is
                        // the one full-bleed item on the screen, so its day
                        // cells clear 48 dp (NF-009).
                        CalendarDatePicker(
                          key: const Key('add-crop-date'),
                          initialDate: _sowingDate ?? _today,
                          firstDate: _today.subtract(const Duration(days: 365)),
                          lastDate: _today,
                          onDateChanged: (date) =>
                              setState(() => _sowingDate = date.toUtc()),
                        ),
                        _Padded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const SizedBox(height: Tokens.space3),
                              Text(l10n.addCropWater, style: app.text.heading),
                              const SizedBox(height: Tokens.space2),
                              ChoiceGrid(
                                children: <Widget>[
                                  for (final value in IrrigationTypes.values)
                                    ChoiceTile(
                                      key: Key('add-irrigation-$value'),
                                      icon: irrigationIcon(value),
                                      label: IrrigationTypes.label(l10n, value),
                                      selected: value == _irrigation,
                                      onTap: () =>
                                          setState(() => _irrigation = value),
                                    ),
                                ],
                              ),
                              const SizedBox(height: Tokens.space4),
                              Text(l10n.addCropSoil, style: app.text.heading),
                              const SizedBox(height: Tokens.space2),
                              ChoiceGrid(
                                children: <Widget>[
                                  for (final value in SoilTypes.values)
                                    ChoiceTile(
                                      key: Key('add-soil-$value'),
                                      icon: soilIcon(value),
                                      label: SoilTypes.label(l10n, value),
                                      selected: value == _soil,
                                      onTap: () =>
                                          setState(() => _soil = value),
                                    ),
                                ],
                              ),
                              const SizedBox(height: Tokens.space4),
                              AppButton(
                                key: const Key('add-crop-save'),
                                label: l10n.addCropSave,
                                icon: Icons.check,
                                onPressed: !ready || _saving
                                    ? null
                                    : () => _save(farms),
                              ),
                              const SizedBox(height: Tokens.space4),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The screen's side padding, applied per item because the calendar between
/// them is deliberately full-bleed (NF-009: 48 dp day cells).
class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceScreenPadding),
    child: child,
  );
}
