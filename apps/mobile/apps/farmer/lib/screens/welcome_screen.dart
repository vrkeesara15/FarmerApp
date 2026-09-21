import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/farm_edit.dart';
import '../widgets/kisan_widgets.dart';

/// F05 Welcome (FM-003). A farmer registered by a field officer sees "Your
/// farm details from Ramesh (field officer)" with farms (map thumbnail),
/// crops and stages, and confirms or changes simple fields with icon tiles
/// (crop stage, irrigation, soil; no typing). Anyone else gets a quick
/// setup: crop tiles and village from a list, then land size and sowing
/// time. Two decisions per step.
class WelcomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final profile = ref.watch(kisanProfileProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanWelcomeTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: profile.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => ErrorState(
                  onRetry: () =>
                      ref.read(kisanRepositoryProvider).refreshProfile(),
                ),
                data: (cached) {
                  final p = cached?.value;
                  if (p != null &&
                      p.registeredByOfficer &&
                      p.farms.isNotEmpty) {
                    return _ConfirmDetails(profile: p);
                  }
                  return _QuickSetup(profile: p);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _finish(BuildContext context, WidgetRef ref) async {
  await ref.read(kisanRepositoryProvider).markWelcomeDone();
  if (context.mounted) context.go(AppRoutes.home);
}

class _ConfirmDetails extends ConsumerStatefulWidget {
  const _ConfirmDetails({required this.profile});

  final FarmerProfile profile;

  @override
  ConsumerState<_ConfirmDetails> createState() => _ConfirmDetailsState();
}

class _ConfirmDetailsState extends ConsumerState<_ConfirmDetails> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final officer = widget.profile.officer?.firstName;
    final heading = officer == null
        ? l10n.kisanWelcomeFromYourOfficer
        : l10n.kisanWelcomeFromOfficer(officer);
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor: app.tint(app.palette.primaryContainer),
                    child: Icon(
                      Icons.badge_outlined,
                      color: app.palette.primary,
                    ),
                  ),
                  const SizedBox(width: Tokens.space3),
                  Expanded(
                    child: Text(
                      heading,
                      key: const Key('welcome-officer'),
                      style: app.text.title,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space2),
              SpokenText(
                promptId: 'f05_confirm',
                text: _editing
                    ? l10n.kisanWelcomeEditHelp
                    : l10n.kisanWelcomeConfirmHelp,
              ),
              const SizedBox(height: Tokens.space2),
              for (final farm in widget.profile.farms)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.space3),
                  child: FarmSummaryCard(farm: farm, editable: _editing),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppButton(
                key: const Key('welcome-confirm'),
                label: _editing ? l10n.actionDone : l10n.kisanWelcomeCorrect,
                icon: Icons.check,
                onPressed: () => _finish(context, ref),
              ),
              if (!_editing) ...<Widget>[
                const SizedBox(height: Tokens.space2),
                AppButton(
                  key: const Key('welcome-edit'),
                  label: l10n.kisanWelcomeChange,
                  icon: Icons.edit_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => setState(() => _editing = true),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Land size choices (acres).
const List<double> _acreChoices = <double>[1, 2, 5, 10];

/// Sowing time choices: days ago.
const List<int> _sownDaysAgo = <int>[3, 15, 60, 100];

class _QuickSetup extends ConsumerStatefulWidget {
  const _QuickSetup({required this.profile});

  final FarmerProfile? profile;

  @override
  ConsumerState<_QuickSetup> createState() => _QuickSetupState();
}

class _QuickSetupState extends ConsumerState<_QuickSetup> {
  int _step = 0;
  String? _cropId;
  String? _villageId;
  double? _acres;
  int? _daysAgo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _villageId = widget.profile?.villageId;
  }

  Future<void> _save() async {
    final l10n = CoreLocalizations.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(kisanRepositoryProvider)
        .quickSetup(
          cropId: _cropId!,
          villageId: _villageId,
          areaAcres: _acres!,
          sowingDate: ref
              .read(clockProvider)()
              .subtract(Duration(days: _daysAgo!)),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case KisanWrite.done || KisanWrite.queued:
        await _finish(context, ref);
      case KisanWrite.offline:
        showKisanMessage(context, l10n.kisanNeedsInternet);
      case KisanWrite.refused:
        showKisanMessage(context, l10n.kisanSaveFailed);
    }
  }

  String _acreLabel(CoreLocalizations l10n, double a) =>
      a >= 10 ? l10n.kisanAcresPlus('10') : l10n.kisanAcres(formatAcres(a));

  String _sownLabel(CoreLocalizations l10n, int days) => switch (days) {
    3 => l10n.kisanSownThisWeek,
    15 => l10n.kisanSownThisMonth,
    60 => l10n.kisanSownTwoMonths,
    _ => l10n.kisanSownLonger,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final crops = ref.watch(cropsProvider).value ?? const <CropRef>[];
    final villages = ref.watch(villagesProvider).value ?? const <Village>[];
    final lang = Localizations.localeOf(context).languageCode;
    final first = _step == 0;
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
            children: first
                ? <Widget>[
                    SpokenText(
                      promptId: 'f05_setup_crop',
                      text: l10n.kisanSetupCropQuestion,
                      style: app.text.heading,
                    ),
                    ChoiceGrid(
                      children: <Widget>[
                        for (final c in crops)
                          ChoiceTile(
                            key: Key('setup-crop-${c.code}'),
                            icon: Icons.grass,
                            label: c.nameIn(lang),
                            selected: _cropId == c.id,
                            onTap: () => setState(() => _cropId = c.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: Tokens.space4),
                    SpokenText(
                      promptId: 'f05_setup_village',
                      text: l10n.kisanSetupVillageQuestion,
                      style: app.text.heading,
                    ),
                    if (villages.isEmpty)
                      Text(
                        l10n.kisanSetupNoVillages,
                        style: app.text.body.copyWith(
                          color: app.palette.textSecondary,
                        ),
                      ),
                    for (final v in villages)
                      Card(
                        child: ListTile(
                          key: Key('setup-village-${v.id}'),
                          minTileHeight: Tokens.sizeTouchTargetMin + 8,
                          leading: Icon(
                            _villageId == v.id
                                ? Icons.check_circle
                                : Icons.location_city_outlined,
                            color: _villageId == v.id
                                ? app.palette.primary
                                : app.palette.textSecondary,
                          ),
                          title: Text(v.name, style: app.text.label),
                          subtitle: v.mandal.isEmpty ? null : Text(v.mandal),
                          selected: _villageId == v.id,
                          onTap: () => setState(() => _villageId = v.id),
                        ),
                      ),
                  ]
                : <Widget>[
                    SpokenText(
                      promptId: 'f05_setup_land',
                      text: l10n.kisanSetupLandQuestion,
                      style: app.text.heading,
                    ),
                    ChoiceGrid(
                      columns: 2,
                      children: <Widget>[
                        for (final a in _acreChoices)
                          ChoiceTile(
                            key: Key('setup-acres-${a.toInt()}'),
                            icon: Icons.crop_square,
                            label: _acreLabel(l10n, a),
                            selected: _acres == a,
                            onTap: () => setState(() => _acres = a),
                          ),
                      ],
                    ),
                    const SizedBox(height: Tokens.space4),
                    SpokenText(
                      promptId: 'f05_setup_sown',
                      text: l10n.kisanSetupSownQuestion,
                      style: app.text.heading,
                    ),
                    ChoiceGrid(
                      columns: 2,
                      children: <Widget>[
                        for (final d in _sownDaysAgo)
                          ChoiceTile(
                            key: Key('setup-sown-$d'),
                            icon: Icons.calendar_month_outlined,
                            label: _sownLabel(l10n, d),
                            selected: _daysAgo == d,
                            onTap: () => setState(() => _daysAgo = d),
                          ),
                      ],
                    ),
                  ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppButton(
                key: const Key('setup-next'),
                label: first ? l10n.actionNext : l10n.kisanSave,
                icon: first ? Icons.arrow_forward : Icons.check,
                loading: _busy,
                onPressed: first
                    ? (_cropId == null ? null : () => setState(() => _step = 1))
                    : (_acres == null || _daysAgo == null || _busy
                          ? null
                          : _save),
              ),
              AppButton(
                key: const Key('setup-skip'),
                label: first ? l10n.kisanSkipForNow : l10n.actionBack,
                variant: AppButtonVariant.tertiary,
                onPressed: first
                    ? () => _finish(context, ref)
                    : () => setState(() => _step = 0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
