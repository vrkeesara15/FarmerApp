import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wizard_copy.dart';

/// A21e: summary of farmer, farms with crops, consent; "Will sync when
/// online" note; the Save button lives in the wizard's bottom bar.
class ReviewStep extends ConsumerWidget {
  /// Creates the step.
  const ReviewStep({this.showIssues = false, super.key});

  /// Show blocking issues (after a failed Save).
  final bool showIssues;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(registrationProvider);
    final wizard = ref.read(registrationProvider.notifier);
    final draft = state.draft!;
    final villages = ref.watch(villagesProvider).value ?? const <Village>[];
    final crops = <String, CropRef>{
      for (final c in ref.watch(cropsProvider).value ?? CropRef.pilotFallback)
        c.id: c,
    };
    final village = villages.where((v) => v.id == draft.villageId).firstOrNull;
    final issues = showIssues
        ? wizard.issuesFor(RegistrationStep.review)
        : const <StepIssue>[];
    final verified = switch (draft.verification) {
      PhoneVerification.verified => l10n.regPhoneVerified,
      PhoneVerification.verifyLater => l10n.regVerifyLaterChosen,
      _ => l10n.farmerPhoneUnverified,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (issues.isNotEmpty)
          NoticeBox(
            key: const Key('reg-review-issues'),
            text: issues.map((i) => issueText(l10n, i)).join('\n'),
            icon: Icons.error_outline,
            color: p.statusDanger,
            container: p.statusDangerContainer,
          ),
        SectionTitle(
          l10n.regReviewFarmer,
          trailing: AppButton(
            key: const Key('reg-edit-basics'),
            label: l10n.regEdit,
            variant: AppButtonVariant.tertiary,
            size: AppButtonSize.medium,
            expand: false,
            icon: Icons.edit_outlined,
            onPressed: () => unawaited(wizard.goTo(RegistrationStep.basics)),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space3),
            child: Column(
              children: <Widget>[
                FactRow(
                  label: l10n.regNameLabel,
                  value: draft.name,
                  icon: Icons.person_outline,
                ),
                FactRow(
                  label: l10n.profilePhone,
                  value: '${l10n.phonePrefix} ${draft.phone} · $verified',
                  icon: Icons.phone_outlined,
                ),
                FactRow(
                  label: l10n.regVillageLabel,
                  value: village?.name ?? draft.villageName,
                  icon: Icons.place_outlined,
                ),
                if (draft.landmark.isNotEmpty)
                  FactRow(
                    label: l10n.regLandmarkLabel,
                    value: draft.landmark,
                    icon: Icons.flag_outlined,
                  ),
                FactRow(
                  label: l10n.profileLanguage,
                  value:
                      LanguageOption.launchLanguages
                          .where((o) => o.locale.languageCode == draft.language)
                          .firstOrNull
                          ?.nativeName ??
                      '—',
                  icon: Icons.translate,
                ),
                if (draft.landOwnership != null)
                  FactRow(
                    label: l10n.profileOwnership,
                    value: LandOwnershipTypes.label(l10n, draft.landOwnership!),
                    icon: Icons.home_outlined,
                  ),
              ],
            ),
          ),
        ),
        SectionTitle(l10n.regReviewFarms),
        for (final (i, farm) in draft.farms.indexed) ...<Widget>[
          if (i > 0) const SizedBox(height: Tokens.space3),
          Card(
            key: Key('reg-review-farm-$i'),
            child: Padding(
              padding: const EdgeInsets.all(Tokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          farm.name.isEmpty
                              ? l10n.regFarmIndex(i + 1)
                              : farm.name,
                          style: app.text.heading,
                        ),
                      ),
                      AppButton(
                        key: Key('reg-edit-farm-$i'),
                        label: l10n.regEdit,
                        variant: AppButtonVariant.tertiary,
                        size: AppButtonSize.medium,
                        expand: false,
                        icon: Icons.edit_outlined,
                        onPressed: () => unawaited(
                          wizard.selectFarm(i, step: RegistrationStep.boundary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Tokens.space2),
                  MapPanel(
                    boundary: farm.boundary,
                    interactive: false,
                    height: 140,
                    tileProvider: ref.watch(mapTileProviderProvider),
                  ),
                  const SizedBox(height: Tokens.space2),
                  FactRow(
                    label: l10n.regAreaLabel,
                    value: farm.declaredAcres == null
                        ? '—'
                        : '${l10n.profileAcres(acresText(farm.declaredAcres!))} · '
                              '${l10n.regComputedArea(acresText(farm.computedAcres))}',
                    icon: Icons.square_foot_outlined,
                  ),
                  if (farm.soil != null)
                    FactRow(
                      label: l10n.regSoilLabel,
                      value: SoilTypes.label(l10n, farm.soil!),
                      icon: Icons.layers_outlined,
                    ),
                  if (farm.irrigation != null)
                    FactRow(
                      label: l10n.regIrrigationLabel,
                      value: IrrigationTypes.label(l10n, farm.irrigation!),
                      icon: Icons.water_drop_outlined,
                    ),
                  if (farm.photos.isNotEmpty)
                    FactRow(
                      label: l10n.regFarmPhoto,
                      value: l10n.regFarmPhotosCount(farm.photos.length),
                      icon: Icons.photo_outlined,
                    ),
                  const SizedBox(height: Tokens.space2),
                  Wrap(
                    spacing: Tokens.space2,
                    runSpacing: Tokens.space2,
                    children: <Widget>[
                      for (final plot in farm.plots)
                        CropChip(
                          data: CropChipData(
                            name: plot.cropId == null
                                ? '—'
                                : cropName(
                                    context,
                                    crops[plot.cropId] ??
                                        CropRef(
                                          id: plot.cropId!,
                                          code: plot.cropId!,
                                          name: plot.cropId!,
                                        ),
                                  ),
                            stage: plot.sowingDate == null
                                ? null
                                : '${formatDateDdMmYyyy(plot.sowingDate!)} · '
                                      '${Seasons.label(l10n, plot.season!)}',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: Tokens.space2),
        AppButton(
          key: const Key('reg-review-add-farm'),
          label: l10n.regAddFarm,
          variant: AppButtonVariant.tertiary,
          size: AppButtonSize.medium,
          icon: Icons.add_location_alt_outlined,
          onPressed: () => unawaited(wizard.addFarm()),
        ),
        SectionTitle(l10n.regReviewConsent),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space3),
            child: Column(
              children: <Widget>[
                FactRow(
                  label: l10n.consentDataCardTitle,
                  value: draft.consentData
                      ? l10n.consentGiven
                      : l10n.consentNotGiven,
                  icon: Icons.verified_user_outlined,
                ),
                FactRow(
                  label: l10n.consentOffersCardTitle,
                  value: draft.consentMarketing
                      ? l10n.consentGiven
                      : l10n.consentNotGiven,
                  icon: Icons.campaign_outlined,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Tokens.space4),
        NoticeBox(
          key: const Key('reg-will-sync'),
          text: '${l10n.farmerPendingSync}. ${l10n.regReviewSyncNote}',
          icon: Icons.cloud_upload_outlined,
          color: p.statusInfo,
          container: p.statusInfoContainer,
        ),
      ],
    );
  }
}
