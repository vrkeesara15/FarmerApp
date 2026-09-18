import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../farmers/wizard_copy.dart';
import 'visit_copy.dart';

/// A30 Start visit (FA-014): farmer / farm, purpose, the client-side
/// geofence pre-check on a mini MapPanel (green ring inside, explanation +
/// "Request override" with a note outside) and Check in. Requires duty on.
class StartVisitScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [farmerId] / [farmId] come from A22.
  const StartVisitScreen({this.farmerId, this.farmId, super.key});

  /// Preselected farmer.
  final String? farmerId;

  /// Preselected farm.
  final String? farmId;

  @override
  ConsumerState<StartVisitScreen> createState() => _StartVisitScreenState();
}

class _StartVisitScreenState extends ConsumerState<StartVisitScreen> {
  late String? _farmerId = widget.farmerId;
  late String? _farmId = widget.farmId;
  VisitPurpose _purpose = VisitPurpose.advisory;
  VisitPrecheck? _precheck;
  bool? _onDuty;
  bool _locating = false;
  bool _override = false;
  bool _busy = false;
  bool _noteMissing = false;
  final TextEditingController _note = TextEditingController();

  VisitFlow get _flow => ref.read(visitFlowProvider);

  @override
  void initState() {
    super.initState();
    _loadDuty();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadDuty() async {
    final on = await _flow.onDuty();
    if (!mounted) return;
    setState(() => _onDuty = on);
    if (on && _farmerId != null) await _check();
  }

  Future<void> _check() async {
    final farmerId = _farmerId;
    if (farmerId == null) return;
    setState(() => _locating = true);
    final detail = await ref.read(farmerRepositoryProvider).farmer(farmerId);
    final farm = detail?.farms
        .where((f) => f.farm.id == _farmId)
        .firstOrNull
        ?.farm;
    final pre = await _flow.precheck(farm: farm, village: detail?.village);
    if (!mounted) return;
    setState(() {
      _precheck = pre;
      _locating = false;
      _override = _override && !(pre.check?.allowed ?? false);
    });
  }

  Future<void> _selectFarmer(FarmerDetail detail) async {
    setState(() {
      _farmerId = detail.farmer.id;
      _farmId = detail.farms.isEmpty ? null : detail.farms.first.farm.id;
      _precheck = null;
    });
    await _check();
  }

  Future<void> _checkIn(FarmerDetail detail) async {
    final pre = _precheck;
    if (pre == null) return;
    final allowed = pre.check?.allowed ?? false;
    if (!allowed && _note.text.trim().isEmpty) {
      setState(() => _noteMissing = true);
      return;
    }
    setState(() => _busy = true);
    final out = await _flow.checkIn(
      farmerId: detail.farmer.id,
      farmId: _farmId,
      villageId: detail.farmer.villageId,
      purpose: _purpose,
      precheck: pre,
      overrideNote: allowed ? null : _note.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (out.result) {
      case CheckInResult.started:
        context.pushReplacement(VisitRoutes.visit(out.visitId!));
      case CheckInResult.offDuty:
        setState(() => _onDuty = false);
      case CheckInResult.noFix:
        await _check();
      case CheckInResult.needsOverride:
        setState(() => _noteMissing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final onDuty = _onDuty;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.actionStartVisit),
        actions: <Widget>[
          SyncStatusPillLive(onTap: () => context.push(AppRoutes.syncDetails)),
          const SizedBox(width: Tokens.space3),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: onDuty == null
                  ? const Center(child: CircularProgressIndicator())
                  : !onDuty
                  ? EmptyState(
                      key: const Key('visit-off-duty'),
                      icon: Icons.work_off_outlined,
                      title: l10n.visitOffDutyTitle,
                      help: l10n.visitOffDutyBody,
                      actionLabel: l10n.visitGoHome,
                      onAction: () => context.go(AppRoutes.home),
                    )
                  : _farmerId == null
                  ? _FarmerPicker(onSelected: _selectFarmer)
                  : _body(context, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CoreLocalizations l10n) {
    final detail = ref.watch(farmerDetailProvider(_farmerId!)).value;
    if (detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final app = context.app;
    final p = app.palette;
    final pre = _precheck;
    final check = pre?.check;
    final farm = detail.farms.where((f) => f.farm.id == _farmId).firstOrNull;
    final allowed = check?.allowed ?? false;
    final fix = pre?.fix;
    return VisitScroll(
      children: <Widget>[
        Text(detail.farmer.name, style: app.text.title),
        if (detail.village != null)
          Text(
            detail.village!.name,
            style: app.text.body.copyWith(color: p.textSecondary),
          ),
        if (detail.farms.length > 1) ...<Widget>[
          const SizedBox(height: Tokens.space3),
          ChoiceChips(
            label: l10n.visitFarmLabel,
            values: <String>[for (final f in detail.farms) f.farm.id],
            labelOf: (id) {
              final i = detail.farms.indexWhere((f) => f.farm.id == id);
              return detail.farms[i].farm.name ?? l10n.regFarmIndex(i + 1);
            },
            iconOf: (_) => Icons.grass_outlined,
            selected: _farmId,
            keyPrefix: 'visit-farm-',
            onSelected: (id) {
              setState(() => _farmId = id);
              _check();
            },
          ),
        ],
        const SizedBox(height: Tokens.space3),
        ChoiceChips(
          label: l10n.visitPurposeLabel,
          values: <String>[for (final v in VisitPurpose.values) v.name],
          labelOf: (v) => purposeOf(v).label(l10n),
          iconOf: (v) => purposeOf(v).icon,
          selected: _purpose.name,
          keyPrefix: 'visit-purpose-',
          onSelected: (v) => setState(() => _purpose = purposeOf(v)),
        ),
        const SizedBox(height: Tokens.space4),
        MapPanel(
          key: const Key('visit-map'),
          boundary: farm?.boundary ?? const <GeoPoint>[],
          interactive: false,
          height: 180,
          showCorners: false,
          tileProvider: ref.watch(mapTileProviderProvider),
          currentPosition: fix == null
              ? null
              : GeoFix(
                  point: fix.point,
                  accuracyMetres: fix.accuracyM,
                  time: fix.time,
                ),
          geofence: check == null
              ? GeofenceHighlight.none
              : allowed
              ? GeofenceHighlight.inside
              : GeofenceHighlight.outside,
          meetingPoint: pre?.meetingPoint,
          meetingRadiusM: pre?.meetingPoint == null
              ? null
              : detail.village?.meetingPointRadiusM ??
                    pre!.settings.geofenceRadiusM,
        ),
        if (farm != null && farm.boundary.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Text(
              l10n.visitFarmNoBoundary,
              style: app.text.caption.copyWith(color: p.textSecondary),
            ),
          ),
        const SizedBox(height: Tokens.space3),
        if (_locating)
          Row(
            key: const Key('visit-locating'),
            children: <Widget>[
              const SizedBox.square(
                dimension: Tokens.space4,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: Tokens.space2),
              Text(l10n.visitLocating, style: app.text.body),
            ],
          )
        else if (pre != null && check == null)
          VisitNotice(
            key: const Key('visit-no-fix'),
            text: l10n.visitNoFix,
            tone: 'danger',
            icon: Icons.location_disabled_outlined,
          )
        else if (check != null) ...<Widget>[
          VisitNotice(
            key: Key(allowed ? 'visit-inside' : 'visit-outside'),
            tone: allowed ? 'success' : 'danger',
            icon: allowed ? Icons.my_location : Icons.wrong_location_outlined,
            text: switch (check.outcome) {
              GeofenceOutcome.inside => l10n.visitInsideGeofence,
              GeofenceOutcome.meetingPoint => l10n.visitAtMeetingPoint,
              GeofenceOutcome.outside =>
                check.distanceM == null
                    ? l10n.visitNoTarget
                    : check.target == 'meeting_point'
                    ? l10n.visitOutsideMeeting(
                        check.distanceM!.round(),
                        check.radiusM.round(),
                      )
                    : l10n.visitOutsideFarm(
                        check.distanceM!.round(),
                        check.radiusM.round(),
                      ),
            },
          ),
          if (fix != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.space1),
              child: Text(
                l10n.visitAccuracy(fix.accuracyM.round()),
                style: app.text.caption.copyWith(color: p.textSecondary),
              ),
            ),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            key: const Key('visit-refresh'),
            label: l10n.visitRefreshLocation,
            icon: Icons.gps_fixed,
            variant: AppButtonVariant.tertiary,
            size: AppButtonSize.medium,
            expand: false,
            onPressed: _locating ? null : _check,
          ),
        ),
        if (check != null && !allowed) ...<Widget>[
          if (!_override)
            AppButton(
              key: const Key('visit-request-override'),
              label: l10n.visitRequestOverride,
              icon: Icons.edit_note,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              onPressed: () => setState(() => _override = true),
            )
          else ...<Widget>[
            AppTextField(
              key: const Key('visit-override-note'),
              label: l10n.visitOverrideNoteLabel,
              hintText: l10n.visitOverrideNoteHint,
              controller: _note,
              errorText: _noteMissing ? l10n.visitOverrideNoteRequired : null,
              onChanged: (_) {
                if (_noteMissing) setState(() => _noteMissing = false);
              },
            ),
            const SizedBox(height: Tokens.space1),
            Text(
              l10n.visitOverrideHelp,
              style: app.text.caption.copyWith(color: p.textSecondary),
            ),
          ],
        ],
        const SizedBox(height: Tokens.space4),
        AppButton(
          key: const Key('visit-check-in'),
          label: allowed ? l10n.visitCheckIn : l10n.visitCheckInOverride,
          icon: Icons.login,
          loading: _busy,
          onPressed: check == null || (!allowed && !_override) || _busy
              ? null
              : () => _checkIn(detail),
        ),
        const SizedBox(height: Tokens.space6),
      ],
    );
  }
}

class _FarmerPicker extends ConsumerWidget {
  const _FarmerPicker({required this.onSelected});

  final ValueChanged<FarmerDetail> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final farmers =
        ref.watch(farmerListProvider(const FarmerListFilter())).value ??
        const <FarmerSummary>[];
    if (farmers.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: l10n.farmersEmptyTitle,
        help: l10n.farmersEmptyHelp,
      );
    }
    return VisitScroll(
      children: <Widget>[
        SectionTitle(l10n.visitChooseFarmer),
        for (final f in farmers)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space2),
            child: FarmerCard(
              key: Key('visit-farmer-${f.id}'),
              name: f.name,
              village: f.villageName,
              crops: <CropChipData>[
                for (final c in f.crops)
                  CropChipData(name: cropName(context, c)),
              ],
              onTap: () async {
                final detail = await ref
                    .read(farmerRepositoryProvider)
                    .farmer(f.id);
                if (detail != null) onSelected(detail);
              },
            ),
          ),
      ],
    );
  }
}
