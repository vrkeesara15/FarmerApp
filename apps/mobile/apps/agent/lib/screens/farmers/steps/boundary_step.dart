import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wizard_copy.dart';

/// A21b: farm boundary on the map (walk-around with live polygon, or tap
/// four corners), accuracy indicator, area in acres with the VA-F03
/// warning, soil, irrigation, ownership and an optional farm photo.
class BoundaryStep extends ConsumerWidget {
  /// Creates the step.
  const BoundaryStep({this.showIssues = false, super.key});

  /// Show validation errors (after a failed Next).
  final bool showIssues;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(registrationProvider);
    final wizard = ref.read(registrationProvider.notifier);
    final draft = state.draft!;
    final farm = draft.farm!;
    final issues = showIssues
        ? wizard.issuesFor(RegistrationStep.boundary)
        : const <StepIssue>[];
    final walk = farm.mode == BoundaryMode.walk;
    final selfIntersecting =
        farm.boundary.length >= 3 && isSelfIntersecting(farm.boundary);
    final fix = state.lastFix;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (draft.farms.length > 1) ...<Widget>[
          Text(
            l10n.regFarmIndex(draft.currentFarm + 1),
            style: app.text.label.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: Tokens.space2),
        ],
        SegmentedButton<BoundaryMode>(
          segments: <ButtonSegment<BoundaryMode>>[
            ButtonSegment<BoundaryMode>(
              value: BoundaryMode.walk,
              icon: const Icon(Icons.directions_walk),
              label: Text(
                l10n.regBoundaryWalk,
                key: const Key('reg-mode-walk'),
              ),
            ),
            ButtonSegment<BoundaryMode>(
              value: BoundaryMode.tap,
              icon: const Icon(Icons.touch_app_outlined),
              label: Text(l10n.regBoundaryTap, key: const Key('reg-mode-tap')),
            ),
          ],
          selected: <BoundaryMode>{farm.mode},
          onSelectionChanged: (s) => unawaited(wizard.setBoundaryMode(s.first)),
        ),
        const SizedBox(height: Tokens.space3),
        Text(
          walk ? l10n.regWalkHint : l10n.regTapHint,
          style: app.text.body.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: Tokens.space3),
        MapPanel(
          key: const Key('reg-map'),
          boundary: farm.boundary,
          closed: !walk || farm.closed || !state.walking,
          currentPosition: fix,
          center: fix?.point,
          onTap: walk ? null : (pt) => unawaited(wizard.addCorner(pt)),
          tileProvider: ref.watch(mapTileProviderProvider),
        ),
        const SizedBox(height: Tokens.space2),
        Row(
          children: <Widget>[
            Icon(Icons.timeline, size: Tokens.space4, color: p.textSecondary),
            const SizedBox(width: Tokens.space1),
            Text(
              l10n.regPointsCount(farm.boundary.length),
              style: app.text.caption.copyWith(color: p.textSecondary),
            ),
            const SizedBox(width: Tokens.space3),
            if (farm.boundary.length >= 3)
              Expanded(
                child: Text(
                  l10n.regComputedArea(acresText(farm.computedAcres)),
                  key: const Key('reg-computed-area'),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
              ),
          ],
        ),
        if (walk) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          _AccuracyRow(fix: fix, walking: state.walking),
          if (state.location == LocationAvailability.serviceDisabled ||
              state.location ==
                  LocationAvailability.permissionDenied) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            NoticeBox(
              text: state.location == LocationAvailability.serviceDisabled
                  ? l10n.regLocationOff
                  : l10n.regLocationDenied,
              icon: Icons.location_off_outlined,
              color: p.statusWarning,
              container: p.statusWarningContainer,
            ),
          ],
          const SizedBox(height: Tokens.space3),
          Row(
            children: <Widget>[
              Expanded(
                child: state.walking
                    ? AppButton(
                        key: const Key('reg-stop-walk'),
                        label: l10n.regStopWalk,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.medium,
                        icon: Icons.pause,
                        onPressed: wizard.stopWalk,
                      )
                    : AppButton(
                        key: const Key('reg-start-walk'),
                        label: l10n.regStartWalk,
                        size: AppButtonSize.medium,
                        icon: Icons.play_arrow,
                        onPressed: farm.closed ? null : wizard.startWalk,
                      ),
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: AppButton(
                  key: const Key('reg-close-polygon'),
                  label: l10n.regClosePolygon,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  icon: Icons.check_circle_outline,
                  onPressed: farm.boundary.length >= 3 && !farm.closed
                      ? wizard.closePolygon
                      : null,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Tokens.space2),
        Wrap(
          spacing: Tokens.space2,
          runSpacing: Tokens.space2,
          children: <Widget>[
            AppButton(
              key: const Key('reg-undo-point'),
              label: l10n.regUndoPoint,
              variant: AppButtonVariant.tertiary,
              size: AppButtonSize.medium,
              expand: false,
              icon: Icons.undo,
              onPressed: farm.boundary.isEmpty ? null : wizard.undoPoint,
            ),
            AppButton(
              key: const Key('reg-clear-boundary'),
              label: l10n.regClearBoundary,
              variant: AppButtonVariant.tertiary,
              size: AppButtonSize.medium,
              expand: false,
              icon: Icons.delete_outline,
              onPressed: farm.boundary.isEmpty ? null : wizard.clearBoundary,
            ),
          ],
        ),
        if (selfIntersecting ||
            issues.contains(StepIssue.boundaryTooFewPoints)) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          NoticeBox(
            key: const Key('reg-boundary-issue'),
            text: selfIntersecting
                ? l10n.regBoundaryInvalid
                : l10n.regIssueBoundary,
            icon: Icons.error_outline,
            color: p.statusDanger,
            container: p.statusDangerContainer,
          ),
        ],
        const SizedBox(height: Tokens.space4),
        DraftTextField(
          fieldKey: const Key('reg-area'),
          label: l10n.regAreaLabel,
          value: farm.declaredAcres == null ? '' : _trim(farm.declaredAcres!),
          hintText: l10n.regAreaHint,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          prefixIcon: Icons.square_foot_outlined,
          errorText: issues.contains(StepIssue.areaRequired)
              ? l10n.regIssueArea
              : null,
          onChanged: (v) => unawaited(
            wizard.setDeclaredAcres(double.tryParse(v.replaceAll(',', '.'))),
          ),
        ),
        if (farm.boundary.length >= 3)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              key: const Key('reg-use-measured'),
              label: l10n.regUseMeasured,
              variant: AppButtonVariant.tertiary,
              size: AppButtonSize.medium,
              expand: false,
              icon: Icons.straighten,
              onPressed: wizard.useComputedAcres,
            ),
          ),
        if (farm.areaMismatch) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          NoticeBox(
            key: const Key('reg-area-warning'),
            text: l10n.regAreaWarning,
            icon: Icons.warning_amber_outlined,
            color: p.statusWarning,
            container: p.statusWarningContainer,
          ),
        ],
        const SizedBox(height: Tokens.space4),
        DraftTextField(
          fieldKey: const Key('reg-farm-name'),
          label: l10n.regFarmNameLabel,
          value: farm.name,
          hintText: l10n.regFarmNameHint,
          prefixIcon: Icons.grass_outlined,
          onChanged: (v) => unawaited(wizard.setFarmName(v)),
        ),
        const SizedBox(height: Tokens.space4),
        ChoiceChips(
          label: l10n.regSoilLabel,
          keyPrefix: 'reg-soil-',
          values: SoilTypes.values,
          labelOf: (v) => SoilTypes.label(l10n, v),
          iconOf: (_) => Icons.layers_outlined,
          selected: farm.soil,
          onSelected: (v) => unawaited(wizard.setSoil(v)),
        ),
        const SizedBox(height: Tokens.space4),
        ChoiceChips(
          label: l10n.regIrrigationLabel,
          keyPrefix: 'reg-irrigation-',
          values: IrrigationTypes.values,
          labelOf: (v) => IrrigationTypes.label(l10n, v),
          iconOf: (_) => Icons.water_drop_outlined,
          selected: farm.irrigation,
          onSelected: (v) => unawaited(wizard.setIrrigation(v)),
        ),
        const SizedBox(height: Tokens.space4),
        ChoiceChips(
          label: l10n.regOwnershipLabel,
          keyPrefix: 'reg-farm-own-',
          values: LandOwnershipTypes.values,
          labelOf: (v) => LandOwnershipTypes.label(l10n, v),
          iconOf: (v) => v == LandOwnershipTypes.own
              ? Icons.home_outlined
              : Icons.handshake_outlined,
          selected: farm.ownership ?? draft.landOwnership,
          onSelected: (v) => unawaited(wizard.setFarmOwnership(v)),
        ),
        const SizedBox(height: Tokens.space4),
        _PhotoSection(state: state),
      ],
    );
  }

  static String _trim(double v) => v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _AccuracyRow extends StatelessWidget {
  const _AccuracyRow({required this.fix, required this.walking});

  final GeoFix? fix;
  final bool walking;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final f = fix;
    final color = f == null
        ? p.textSecondary
        : f.accuracyMetres <= 10
        ? p.statusSuccess
        : f.accuracyMetres <= 25
        ? p.statusWarning
        : p.statusDanger;
    return Row(
      key: const Key('reg-accuracy'),
      children: <Widget>[
        Icon(
          f == null ? Icons.gps_not_fixed : Icons.gps_fixed,
          size: Tokens.sizeIcon,
          color: color,
        ),
        const SizedBox(width: Tokens.space2),
        Expanded(
          child: Text(
            f == null
                ? (walking ? l10n.regAccuracyWaiting : l10n.regAccuracyWaiting)
                : l10n.regAccuracy(f.accuracyMetres.round()),
            style: app.text.label.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _PhotoSection extends ConsumerWidget {
  const _PhotoSection({required this.state});

  final RegistrationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final wizard = ref.read(registrationProvider.notifier);
    final farm = state.draft!.farm!;
    final pending = state.pendingPhoto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.regFarmPhoto,
          style: app.text.label.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: Tokens.space2),
        if (pending != null)
          PhotoReviewCard(
            sizeBytes: pending.processed.bytes.length,
            width: pending.processed.width,
            height: pending.processed.height,
            quality: pending.quality,
            thumbnail: MemoryImage(pending.processed.bytes),
            onRetake: () {
              wizard.retakePhoto();
              unawaited(wizard.takePhoto());
            },
            onUse: () => unawaited(wizard.usePhoto()),
          )
        else ...<Widget>[
          for (final (i, photo) in farm.photos.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space2),
              child: Row(
                children: <Widget>[
                  Icon(Icons.photo_outlined, color: p.statusSuccess),
                  const SizedBox(width: Tokens.space2),
                  Expanded(
                    child: Text(
                      '${l10n.regPhotoAdded} ${i + 1} · '
                      '${l10n.photoSizeKb(photo.sizeBytes ~/ 1024)}',
                      style: app.text.body,
                    ),
                  ),
                  AppButton(
                    label: l10n.regPhotoRemove,
                    variant: AppButtonVariant.tertiary,
                    size: AppButtonSize.medium,
                    expand: false,
                    onPressed: () =>
                        unawaited(wizard.removePhoto(photo.uploadId)),
                  ),
                ],
              ),
            ),
          AppButton(
            key: const Key('reg-take-photo'),
            label: l10n.regTakePhoto,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.medium,
            icon: Icons.camera_alt_outlined,
            loading: state.photoBusy,
            onPressed: () => unawaited(wizard.takePhoto()),
          ),
        ],
      ],
    );
  }
}
