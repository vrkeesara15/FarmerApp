import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';
import 'crop_doctor_common.dart';

/// F21 Camera (FM-004): live preview with the [CameraGuideOverlay] (leaf
/// frame, hold steady / good light / fill the frame, the last retake tip
/// lit) and a big shutter; every shot goes to F22.
class CropCameraScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CropCameraScreen({super.key});

  @override
  ConsumerState<CropCameraScreen> createState() => _CropCameraScreenState();
}

class _CropCameraScreenState extends ConsumerState<CropCameraScreen> {
  late final GuidedCamera _camera = ref.read(guidedCameraFactoryProvider)();

  Future<void> _onShot(Uint8List bytes) async {
    final capture = ref.read(cropDoctorCaptureProvider.notifier);
    await capture.addShot(bytes);
    if (!mounted) return;
    context.pushReplacement(AppRoutes.cropCheck);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(cropDoctorCaptureProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(l10n.cropDoctorTitle)),
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

/// F22 Photo check (FM-004): the shot's verdict with its retake tip (read
/// aloud when rejected), Retake / Use photo, the photos kept so far (up to
/// 3), Add another, and Continue (to F23 when the crop is not known).
class PhotoCheckScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PhotoCheckScreen({super.key});

  @override
  ConsumerState<PhotoCheckScreen> createState() => _PhotoCheckScreenState();
}

class _PhotoCheckScreenState extends ConsumerState<PhotoCheckScreen> {
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final pending = ref.read(cropDoctorCaptureProvider).pending;
    if (pending != null && !pending.accepted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) speakTip(context, ref, pending.quality.tipKey);
      });
    }
  }

  Future<void> _continue() async {
    final state = ref.read(cropDoctorCaptureProvider);
    if (state.crop == null) {
      await context.push(AppRoutes.cropChoose);
      return;
    }
    setState(() => _submitting = true);
    final id = await ref.read(cropDoctorCaptureProvider.notifier).submit();
    await ref.read(kisanFlushProvider)().catchError((Object _) {});
    if (!mounted) return;
    context.go(AppRoutes.cropResult(id));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(cropDoctorCaptureProvider);
    final crops = ref.watch(cropsProvider).value ?? const <CropRef>[];
    final pending = state.pending;
    final capture = ref.read(cropDoctorCaptureProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.photoReviewHeading)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  if (pending != null) ...<Widget>[
                    PhotoReviewCard(
                      key: const Key('photo-check-pending'),
                      sizeBytes: pending.processed.sizeBytes,
                      width: pending.processed.width,
                      height: pending.processed.height,
                      quality: pending.quality,
                      thumbnail: MemoryImage(pending.processed.bytes),
                      index: state.accepted.length + 1,
                      total: maxDiagnosisPhotos,
                      onRetake: () {
                        capture.retake();
                        context.pushReplacement(AppRoutes.cropCamera);
                      },
                      onUse: capture.usePending,
                    ),
                    if (!pending.accepted)
                      AudioButton(
                        promptId: pending.quality.tipKey.replaceAll('.', '_'),
                        text: l10n.photoTip(pending.quality.tipKey),
                      ),
                  ] else if (state.checking)
                    const Center(child: CircularProgressIndicator()),
                  if (state.accepted.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Tokens.space3),
                    Text(
                      l10n.cropDoctorPhotosReady(state.accepted.length),
                      key: const Key('photo-check-count'),
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
                    if (state.crop != null) ...<Widget>[
                      const SizedBox(height: Tokens.space3),
                      Row(
                        children: <Widget>[
                          Icon(cropIcon(state.crop!.code), color: p.primary),
                          const SizedBox(width: Tokens.space2),
                          Expanded(
                            child: Text(
                              l10n.cropDoctorCropIs(
                                state.crop!.code == 'unknown'
                                    ? l10n.cropDoctorUnknownCrop
                                    : cropCodeName(
                                        context,
                                        crops,
                                        state.crop!.code,
                                      ),
                              ),
                              style: app.text.body,
                            ),
                          ),
                          TextButton(
                            key: const Key('photo-check-change-crop'),
                            onPressed: () => context.push(AppRoutes.cropChoose),
                            child: Text(l10n.cropDoctorChangeCrop),
                          ),
                        ],
                      ),
                    ],
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
                      key: const Key('photo-check-add'),
                      label: l10n.cropDoctorAddPhoto,
                      icon: Icons.add_a_photo_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: () =>
                          context.pushReplacement(AppRoutes.cropCamera),
                    ),
                  if (pending == null && state.canContinue) ...<Widget>[
                    const SizedBox(height: Tokens.space2),
                    AppButton(
                      key: const Key('photo-check-continue'),
                      label: state.crop == null
                          ? l10n.actionContinue
                          : l10n.cropDoctorCheckCrop,
                      icon: Icons.arrow_forward,
                      loading: _submitting,
                      onPressed: _submitting ? null : _continue,
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

/// F23 Choose crop (FM-004 manual override): big crop tiles — the farmer's
/// own crops first, the on-device guess pre-selected only while the
/// `on_device_crop_guess` flag is on — and "I don't know".
class ChooseCropScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ChooseCropScreen({super.key});

  @override
  ConsumerState<ChooseCropScreen> createState() => _ChooseCropScreenState();
}

class _ChooseCropScreenState extends ConsumerState<ChooseCropScreen> {
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final capture = ref.read(cropDoctorCaptureProvider.notifier);
    if (ref.read(cropDoctorCaptureProvider).crop == null) {
      capture.chooseCrop(CropChoice.unknown);
    }
    final id = await capture.submit();
    await ref.read(kisanFlushProvider)().catchError((Object _) {});
    if (!mounted) return;
    context.go(AppRoutes.cropResult(id));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(cropDoctorCaptureProvider);
    final profile = ref.watch(kisanProfileProvider).value?.value;
    final crops = ref.watch(cropsProvider).value ?? const <CropRef>[];
    final choices = cropChoices(context, profile, crops);
    final capture = ref.read(cropDoctorCaptureProvider.notifier);
    final detected = ref.watch(onDeviceCropGuessEnabledProvider)
        ? state.detectedCropCode
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cropDoctorChooseCropTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  SpokenText(
                    promptId: 'f23_choose_crop',
                    text: l10n.cropDoctorChooseCropTitle,
                    style: app.text.title,
                  ),
                  if (detected != null && detected != 'other')
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tokens.space3),
                      child: Text(
                        l10n.cropDoctorDetected(
                          cropCodeName(context, crops, detected),
                        ),
                        key: const Key('crop-detected'),
                        style: app.text.body,
                      ),
                    ),
                  ChoiceGrid(
                    children: <Widget>[
                      for (final (choice, name) in choices)
                        ChoiceTile(
                          key: Key('crop-tile-${choice.code}'),
                          icon: cropIcon(choice.code),
                          label: name,
                          selected: state.crop?.code == choice.code,
                          onTap: () => capture.chooseCrop(choice),
                        ),
                      ChoiceTile(
                        key: const Key('crop-tile-unknown'),
                        icon: cropIcon('unknown'),
                        label: l10n.cropDoctorUnknownCrop,
                        selected: state.crop?.code == CropChoice.unknown.code,
                        onTap: () => capture.chooseCrop(CropChoice.unknown),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Tokens.space3),
              child: AppButton(
                key: const Key('crop-choose-submit'),
                label: l10n.cropDoctorCheckCrop,
                icon: Icons.search,
                loading: _submitting,
                onPressed: _submitting || !state.canContinue ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
