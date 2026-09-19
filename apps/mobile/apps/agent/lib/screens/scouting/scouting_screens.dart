import 'dart:async';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/commerce_copy.dart';

/// Scouting routes (FA-019, SPEC 13.2 A40–A43).
abstract final class ScoutRoutes {
  /// Choose the crop plot of a farmer (entry from A22 Scout / Home).
  static String plot(String farmerId) => '/farmers/$farmerId/scout';

  /// A40 Camera with the guide overlay.
  static String camera(String farmerId) => '/farmers/$farmerId/scout/camera';

  /// A41 Photo review.
  static String review(String farmerId) => '/farmers/$farmerId/scout/review';

  /// A42 / A43 one scouting result.
  static String result(String diagnosisId) => '/scouting/$diagnosisId';
}

String _cropName(BuildContext context, List<CropRef> crops, String? cropId) {
  final lang = Localizations.localeOf(context).languageCode;
  final ref =
      crops.where((c) => c.id == cropId).firstOrNull ??
      CropRef.pilotFallback.where((c) => c.id == cropId).firstOrNull;
  return ref?.nameIn(lang) ?? (cropId ?? '—');
}

String? _cropCode(List<CropRef> crops, String? cropId) =>
    (crops.where((c) => c.id == cropId).firstOrNull ??
            CropRef.pilotFallback.where((c) => c.id == cropId).firstOrNull)
        ?.code;

/// FA-019: pick the crop plot the scouting result is attached to.
class ScoutPlotScreen extends ConsumerWidget {
  /// Creates the screen.
  const ScoutPlotScreen({required this.farmerId, super.key});

  /// Farmer.
  final String farmerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final detail = ref.watch(farmerDetailProvider(farmerId)).value;
    final crops = ref.watch(cropsProvider).value ?? CropRef.pilotFallback;
    final farms = detail?.farms ?? const <FarmDetail>[];
    final plots = <(FarmDetail, CropPlot)>[
      for (final f in farms)
        for (final p in f.plots) (f, p),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scoutTitle)),
      body: SafeArea(
        child: detail == null
            ? const Center(child: CircularProgressIndicator())
            : plots.isEmpty
            ? Center(
                child: EmptyState(
                  key: const Key('scout-no-plots'),
                  icon: Icons.grass,
                  title: l10n.scoutNoPlots,
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  Text(detail.farmer.name, style: app.text.title),
                  const SizedBox(height: Tokens.space1),
                  Text(l10n.scoutChoosePlot, style: app.text.heading),
                  const SizedBox(height: Tokens.space3),
                  for (final (farm, plot) in plots)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tokens.space2),
                      child: Card(
                        child: ListTile(
                          key: Key('scout-plot-${plot.id}'),
                          minTileHeight: 64,
                          leading: const Icon(Icons.eco_outlined),
                          title: Text(
                            l10n.scoutPlotLine(
                              _cropName(context, crops, plot.cropId),
                              farm.farm.name ?? '—',
                            ),
                            style: app.text.heading,
                          ),
                          subtitle: plot.stage == null
                              ? null
                              : Text(plot.stage!, style: app.text.caption),
                          trailing: const Icon(Icons.photo_camera_outlined),
                          onTap: () {
                            ref
                                .read(cropDoctorCaptureProvider.notifier)
                                .start(
                                  subject: 'officer',
                                  farmerId: farmerId,
                                  crop: CropChoice(
                                    code:
                                        _cropCode(crops, plot.cropId) ??
                                        'unknown',
                                    cropId: plot.cropId,
                                    cropPlotId: plot.id,
                                    stage: plot.stage,
                                  ),
                                );
                            context.push(ScoutRoutes.camera(farmerId));
                          },
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// A40 Camera with the CameraGuideOverlay; every shot goes to A41.
class ScoutCameraScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ScoutCameraScreen({required this.farmerId, super.key});

  /// Farmer.
  final String farmerId;

  @override
  ConsumerState<ScoutCameraScreen> createState() => _ScoutCameraScreenState();
}

class _ScoutCameraScreenState extends ConsumerState<ScoutCameraScreen> {
  late final GuidedCamera _camera = ref.read(guidedCameraFactoryProvider)();

  Future<void> _onShot(Uint8List bytes) async {
    await ref.read(cropDoctorCaptureProvider.notifier).addShot(bytes);
    if (!mounted) return;
    context.pushReplacement(ScoutRoutes.review(widget.farmerId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(cropDoctorCaptureProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(l10n.scoutTitle)),
      body: SafeArea(
        child: GuidedCameraView(
          camera: _camera,
          onShot: _onShot,
          busy: state.checking,
          tipKey: state.lastTip == PhotoTipKeys.ok ? null : state.lastTip,
          counter: l10n.cropDoctorPhotoCount(
            (state.accepted.length + 1).clamp(1, maxDiagnosisPhotos),
          ),
        ),
      ),
    );
  }
}

/// A41 Photo review (retake / use, up to 3), then the queued diagnosis.
class ScoutReviewScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ScoutReviewScreen({required this.farmerId, super.key});

  /// Farmer.
  final String farmerId;

  @override
  ConsumerState<ScoutReviewScreen> createState() => _ScoutReviewScreenState();
}

class _ScoutReviewScreenState extends ConsumerState<ScoutReviewScreen> {
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final id = await ref.read(cropDoctorCaptureProvider.notifier).submit();
    await syncIfOnline(ref).catchError((Object _) => false);
    if (!mounted) return;
    context.pushReplacement(ScoutRoutes.result(id));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(cropDoctorCaptureProvider);
    final capture = ref.read(cropDoctorCaptureProvider.notifier);
    final pending = state.pending;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scoutCheckPhotos)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  if (pending != null)
                    PhotoReviewCard(
                      key: const Key('scout-review-pending'),
                      sizeBytes: pending.processed.sizeBytes,
                      width: pending.processed.width,
                      height: pending.processed.height,
                      quality: pending.quality,
                      thumbnail: MemoryImage(pending.processed.bytes),
                      index: state.accepted.length + 1,
                      total: maxDiagnosisPhotos,
                      onRetake: () {
                        capture.retake();
                        context.pushReplacement(
                          ScoutRoutes.camera(widget.farmerId),
                        );
                      },
                      onUse: capture.usePending,
                    ),
                  if (state.accepted.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Tokens.space3),
                    Text(
                      l10n.cropDoctorPhotosReady(state.accepted.length),
                      key: const Key('scout-review-count'),
                      style: app.text.heading,
                    ),
                    const SizedBox(height: Tokens.space2),
                    Wrap(
                      spacing: Tokens.space2,
                      runSpacing: Tokens.space2,
                      children: <Widget>[
                        for (final (i, photo) in state.accepted.indexed)
                          Stack(
                            children: <Widget>[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  Tokens.radiusInput,
                                ),
                                child: Image.memory(
                                  photo.processed.bytes,
                                  width: 96,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton.filledTonal(
                                  tooltip: l10n.cropDoctorRemovePhoto,
                                  onPressed: () => capture.remove(i),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    CheckboxListTile(
                      key: const Key('scout-ask-expert'),
                      value: state.askExpert,
                      onChanged: (v) => capture.setAskExpert(v ?? false),
                      title: Text(l10n.cropDoctorAskExpertToo),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Tokens.space3),
              child: Column(
                children: <Widget>[
                  if (pending == null && state.canAddMore)
                    AppButton(
                      key: const Key('scout-review-add'),
                      label: l10n.cropDoctorAddPhoto,
                      icon: Icons.add_a_photo_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => context.pushReplacement(
                        ScoutRoutes.camera(widget.farmerId),
                      ),
                    ),
                  if (pending == null && state.canContinue) ...<Widget>[
                    const SizedBox(height: Tokens.space2),
                    AppButton(
                      key: const Key('scout-review-submit'),
                      label: l10n.cropDoctorCheckCrop,
                      icon: Icons.search,
                      loading: _submitting,
                      onPressed: _submitting ? null : _submit,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A42 Analysing (queued offline too) and A43 Result (high-confidence and
/// provisional variants), attached to the farmer and the crop plot, with
/// TreatmentCards, ranked ProductCards with OwnBrandBadge and "Create
/// order for farmer" (only when buying is allowed, SPEC 3.4).
class ScoutResultScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ScoutResultScreen({required this.diagnosisId, super.key});

  /// Diagnosis id.
  final String diagnosisId;

  @override
  ConsumerState<ScoutResultScreen> createState() => _ScoutResultScreenState();
}

class _ScoutResultScreenState extends ConsumerState<ScoutResultScreen> {
  DiagnosisPoller? _poller;
  bool? _banner;

  @override
  void initState() {
    super.initState();
    final poller = DiagnosisPoller(
      repository: ref.read(diagnosisRepositoryProvider),
      sleep: ref.read(diagnosisPollSleepProvider),
      flush: ref.read(diagnosisFlushProvider),
    );
    _poller = poller;
    unawaited(
      poller.run(widget.diagnosisId).then<void>((_) {}, onError: (_) {}),
    );
  }

  @override
  void dispose() {
    _poller?.stop();
    super.dispose();
  }

  Future<void> _createOrder(Diagnosis d, ProductOption option) async {
    if (!d.showBuy || d.farmerId == null) return; // SPEC 3.4
    final storeId = d.store?.id;
    final item = await catalogItemForOption(
      ref.read(catalogCacheProvider),
      option,
      storeId: storeId,
    );
    ref.read(cartProvider.notifier)
      ..start(d.farmerId!, storeId: storeId)
      ..addRecommended(item, labelClaimId: option.labelClaimId);
    if (mounted) unawaited(context.push(CommerceRoutes.cart));
  }

  Future<void> _askExpert() async {
    final l10n = CoreLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final (outcome, _) = await ref
        .read(diagnosisRepositoryProvider)
        .askExpert(widget.diagnosisId);
    await syncIfOnline(ref).catchError((Object _) => false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome == AskExpertOutcome.alreadyWithExpert
              ? l10n.cropDoctorAskExpertAlready
              : l10n.cropDoctorAskExpertSent,
        ),
      ),
    );
  }

  Future<void> _callFarmer(Farmer? farmer) async {
    final phone = farmer?.phone;
    if (phone == null) return;
    await ref.read(urlOpenerProvider).open('tel:$phone');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final async = ref.watch(diagnosisProvider(widget.diagnosisId));
    final d = async.value;
    final detail = d?.farmerId == null
        ? null
        : ref.watch(farmerDetailProvider(d!.farmerId!)).value;
    final crops = ref.watch(cropsProvider).value ?? CropRef.pilotFallback;
    if (d != null && _banner == null && !d.status.isWaiting) {
      _banner = d.updateUnseen;
      if (d.updateUnseen) {
        unawaited(
          ref.read(diagnosisRepositoryProvider).markSeen(widget.diagnosisId),
        );
      }
    }
    final plot = detail?.plots.where((x) => x.id == d?.cropPlotId).firstOrNull;
    final header = d == null || detail == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space3),
            child: Row(
              key: const Key('scout-attached'),
              children: <Widget>[
                Icon(Icons.person_pin_outlined, color: p.primary),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    l10n.scoutAttachedTo(
                      detail.farmer.name,
                      _cropName(context, crops, plot?.cropId ?? d.cropId),
                    ),
                    style: app.text.label,
                  ),
                ),
              ],
            ),
          );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scoutTitle)),
      bottomNavigationBar: d == null || d.status.isWaiting
          ? null
          : DiagnosisActionBar(
              diagnosis: d,
              orderLabel: l10n.scoutCreateOrder,
              onOrder: d.showBuy && d.recommended != null
                  ? () => _createOrder(d, d.recommended!)
                  : null,
              callOfficerLabel: l10n.scoutCallFarmer,
              talkLabel: l10n.scoutCallFarmer,
              onCallOfficer: () => _callFarmer(detail?.farmer),
              onAskExpert: _askExpert,
            ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: d == null
                  ? async.hasValue
                        ? EmptyState(
                            icon: Icons.search_off,
                            title: l10n.cropDoctorNotOnPhone,
                          )
                        : const Center(child: CircularProgressIndicator())
                  : d.status.isWaiting
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(
                          Tokens.spaceScreenPadding,
                        ),
                        child: Column(
                          key: Key(
                            d.waitingForNetwork
                                ? 'scout-queued'
                                : 'scout-analysing',
                          ),
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ?header,
                            if (d.waitingForNetwork)
                              Icon(
                                Icons.cloud_upload_outlined,
                                size: 72,
                                color: p.statusInfo,
                              )
                            else
                              const SizedBox(
                                width: 64,
                                height: 64,
                                child: CircularProgressIndicator(),
                              ),
                            const SizedBox(height: Tokens.space3),
                            Text(
                              d.waitingForNetwork
                                  ? l10n.scoutQueuedHelp
                                  : l10n.cropDoctorAnalysing,
                              textAlign: TextAlign.center,
                              style: app.text.title,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                      children: <Widget>[
                        DiagnosisResultView(
                          diagnosis: d,
                          storeLabel: d.store?.name,
                          showUpdatedBanner: _banner ?? false,
                          orderLabel: l10n.scoutCreateOrder,
                          onOrder: d.showBuy
                              ? (option) => _createOrder(d, option)
                              : null,
                          header: header,
                          footer: Text(
                            l10n.scoutProvenance(
                              '${d.modelVersions['on_device'] ?? '—'}',
                              '${d.corpusVersion ?? '—'}',
                            ),
                            key: const Key('scout-provenance'),
                            style: app.text.caption.copyWith(
                              color: p.textSecondary,
                            ),
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

/// A22 Diagnoses tab: the farmer's scouting results and crop checks,
/// newest first (FA-019).
class FarmerDiagnosesList extends ConsumerWidget {
  /// Creates the list.
  const FarmerDiagnosesList({required this.farmerId, super.key});

  /// Farmer.
  final String farmerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final rows =
        ref.watch(farmerDiagnosesProvider(farmerId)).value ??
        const <Diagnosis>[];
    final crops = ref.watch(cropsProvider).value ?? CropRef.pilotFallback;
    if (rows.isEmpty) {
      return Center(
        child: EmptyState(
          key: const Key('profile-diagnoses-empty'),
          icon: Icons.biotech_outlined,
          title: l10n.profileDiagnosesEmpty,
          actionLabel: l10n.scoutNewDiagnosis,
          onAction: () => context.push(ScoutRoutes.plot(farmerId)),
        ),
      );
    }
    return ListView.separated(
      key: const Key('profile-diagnoses'),
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: Tokens.space2),
      itemBuilder: (context, i) {
        final d = rows[i];
        final title =
            d.problem?.nameIn(lang) ??
            (d.isOutOfScope
                ? diagnosisOutOfScopeTitle(l10n, d.outOfScopeReason)
                : l10n.cropDoctorWaiting);
        return Card(
          child: ListTile(
            key: Key('profile-diagnosis-${d.id}'),
            minTileHeight: 64,
            leading: Icon(
              d.status.isWaiting
                  ? Icons.hourglass_top_outlined
                  : Icons.biotech_outlined,
              color: p.primary,
            ),
            title: Text(title, style: app.text.heading),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (d.cropCode != null)
                  Text(
                    _cropName(
                      context,
                      crops,
                      crops.where((c) => c.code == d.cropCode).firstOrNull?.id,
                    ),
                    style: app.text.caption,
                  ),
                if (d.confidence != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Tokens.space1),
                    child: ConfidenceBand(level: d.confidence!),
                  ),
                if (d.capturedAt != null)
                  Text(
                    formatDateTimeIst(d.capturedAt!),
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  ),
              ],
            ),
            onTap: () => context.push(ScoutRoutes.result(d.id)),
          ),
        );
      },
    );
  }
}
