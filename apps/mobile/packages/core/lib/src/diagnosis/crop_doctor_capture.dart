import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../photo/photo_processor.dart';
import '../photo/photo_quality.dart';
import 'diagnosis_providers.dart';
import 'diagnosis_repository.dart';

/// Processes a raw camera shot (NF-004) and runs the on-device gate
/// (DX-001) on the processed JPEG.
class DiagnosisPhotoPipeline {
  /// Creates the pipeline.
  DiagnosisPhotoPipeline({
    required this.model,
    Future<ProcessedPhoto> Function(Uint8List bytes, DateTime captureTime)?
    process,
  }) : _process =
           process ??
           ((bytes, time) => PhotoProcessor.process(bytes, captureTime: time));

  /// Quality model (TFLite or the Laplacian heuristic).
  final OnDeviceQualityModel model;

  final Future<ProcessedPhoto> Function(Uint8List bytes, DateTime captureTime)
  _process;

  /// Runs both steps (each off the UI thread).
  Future<CapturedPhoto> run(
    Uint8List raw, {
    required DateTime captureTime,
  }) async {
    final processed = await _process(raw, captureTime);
    final quality = await model.evaluate(processed.bytes);
    return CapturedPhoto(processed: processed, quality: quality);
  }
}

/// The crop picked (or detected) for a diagnosis.
@immutable
class CropChoice {
  /// Creates the choice.
  const CropChoice({
    required this.code,
    this.cropId,
    this.cropPlotId,
    this.stage,
  });

  /// Crop code (`paddy`, ...); `unknown` for "I don't know".
  final String code;

  /// Server crop id, if known.
  final String? cropId;

  /// The crop plot (scouting, or the farmer's own plot).
  final String? cropPlotId;

  /// Crop stage of that plot.
  final String? stage;

  /// "I don't know the crop".
  static const CropChoice unknown = CropChoice(code: 'unknown');

  @override
  bool operator ==(Object other) =>
      other is CropChoice &&
      other.code == code &&
      other.cropId == cropId &&
      other.cropPlotId == cropPlotId &&
      other.stage == stage;

  @override
  int get hashCode => Object.hash(code, cropId, cropPlotId, stage);
}

/// State of one capture session (F20–F23 / A40–A41).
@immutable
class CaptureState {
  /// Creates the state.
  const CaptureState({
    this.accepted = const <CapturedPhoto>[],
    this.pending,
    this.checking = false,
    this.lastTip,
    this.crop,
    this.cropPickedByUser = false,
    this.detectedCropCode,
    this.detectedCropScore,
    this.farmerId,
    this.subject = 'farmer',
    this.askExpert = false,
    this.error,
  });

  /// Photos the user chose to use (max [maxDiagnosisPhotos]).
  final List<CapturedPhoto> accepted;

  /// The shot under review (F22 / A41).
  final CapturedPhoto? pending;

  /// Processing / checking the last shot.
  final bool checking;

  /// Tip of the last check (lights the overlay tip on retake).
  final String? lastTip;

  /// Crop to diagnose.
  final CropChoice? crop;

  /// The user picked [crop] (a detection never overwrites it).
  final bool cropPickedByUser;

  /// On-device crop guess (only while the `on_device_crop_guess` flag is on).
  final String? detectedCropCode;

  /// Its probability.
  final double? detectedCropScore;

  /// Farmer (scouting).
  final String? farmerId;

  /// `farmer` or `officer`.
  final String subject;

  /// Send to the expert too.
  final bool askExpert;

  /// Last camera / processing error code.
  final String? error;

  /// Room for another photo.
  bool get canAddMore => accepted.length < maxDiagnosisPhotos;

  /// At least one usable photo.
  bool get canContinue => accepted.isNotEmpty;

  /// Copy with overrides; `clearX` resets nullable fields.
  CaptureState copyWith({
    List<CapturedPhoto>? accepted,
    CapturedPhoto? pending,
    bool clearPending = false,
    bool? checking,
    String? lastTip,
    bool clearTip = false,
    CropChoice? crop,
    bool? cropPickedByUser,
    String? detectedCropCode,
    double? detectedCropScore,
    String? farmerId,
    String? subject,
    bool? askExpert,
    String? error,
    bool clearError = false,
  }) => CaptureState(
    accepted: accepted ?? this.accepted,
    pending: clearPending ? null : pending ?? this.pending,
    checking: checking ?? this.checking,
    lastTip: clearTip ? null : lastTip ?? this.lastTip,
    crop: crop ?? this.crop,
    cropPickedByUser: cropPickedByUser ?? this.cropPickedByUser,
    detectedCropCode: detectedCropCode ?? this.detectedCropCode,
    detectedCropScore: detectedCropScore ?? this.detectedCropScore,
    farmerId: farmerId ?? this.farmerId,
    subject: subject ?? this.subject,
    askExpert: askExpert ?? this.askExpert,
    error: clearError ? null : error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      other is CaptureState &&
      listEquals(other.accepted, accepted) &&
      other.pending == pending &&
      other.checking == checking &&
      other.lastTip == lastTip &&
      other.crop == crop &&
      other.cropPickedByUser == cropPickedByUser &&
      other.detectedCropCode == detectedCropCode &&
      other.farmerId == farmerId &&
      other.subject == subject &&
      other.askExpert == askExpert &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(accepted),
    pending,
    checking,
    lastTip,
    crop,
    cropPickedByUser,
    detectedCropCode,
    farmerId,
    subject,
    askExpert,
    error,
  );
}

/// One capture session: shots through the gate, up to three accepted, the
/// crop (detected hint or the user's pick), then the queued diagnosis.
class CropDoctorCapture extends Notifier<CaptureState> {
  @override
  CaptureState build() => const CaptureState();

  /// Starts a fresh session (F20 / A22 Scout).
  void start({String subject = 'farmer', String? farmerId, CropChoice? crop}) =>
      state = CaptureState(
        subject: subject,
        farmerId: farmerId,
        crop: crop,
        cropPickedByUser: crop != null,
      );

  /// Processes and checks a shot; it waits in [CaptureState.pending] for
  /// "Use photo" or "Retake".
  Future<CapturedPhoto?> addShot(Uint8List raw) async {
    state = state.copyWith(
      checking: true,
      clearPending: true,
      clearError: true,
    );
    try {
      final photo = await ref
          .read(diagnosisPhotoPipelineProvider)
          .run(raw, captureTime: ref.read(captureClockProvider)());
      final q = photo.quality;
      state = state.copyWith(
        pending: photo,
        checking: false,
        lastTip: q.tipKey,
      );
      return photo;
    } on PhotoDecodeException {
      state = state.copyWith(checking: false, error: 'decode');
      return null;
    }
  }

  /// "Use photo": keeps the pending shot when it passed the gate.
  bool usePending() {
    final p = state.pending;
    if (p == null || !p.accepted || !state.canAddMore) return false;
    final accepted = <CapturedPhoto>[...state.accepted, p];
    final guess = _bestGuess(accepted);
    final flag = ref.read(onDeviceCropGuessEnabledProvider);
    var next = state.copyWith(
      accepted: accepted,
      clearPending: true,
      clearTip: true,
    );
    if (flag && guess != null) {
      next = next.copyWith(
        detectedCropCode: guess.$1,
        detectedCropScore: guess.$2,
      );
      if (!state.cropPickedByUser && guess.$1 != 'other') {
        next = next.copyWith(crop: CropChoice(code: guess.$1));
      }
    }
    state = next;
    return true;
  }

  /// "Retake": drops the pending shot (its tip stays lit on the camera).
  void retake() => state = state.copyWith(clearPending: true);

  /// Removes an accepted photo.
  void remove(int index) {
    final accepted = <CapturedPhoto>[...state.accepted]..removeAt(index);
    state = state.copyWith(accepted: accepted);
  }

  /// Manual crop override (big crop tiles, F23): always wins.
  void chooseCrop(CropChoice crop) =>
      state = state.copyWith(crop: crop, cropPickedByUser: true);

  /// FM-006 "ask an expert too".
  void setAskExpert(bool value) => state = state.copyWith(askExpert: value);

  (String, double)? _bestGuess(List<CapturedPhoto> photos) {
    (String, double)? best;
    for (final p in photos) {
      final code = p.quality.cropCode;
      final score = p.quality.cropScore;
      if (code == null || score == null) continue;
      if (best == null || score > best.$2) best = (code, score);
    }
    return best;
  }

  /// Queues the diagnosis (photos, uploads, create op); returns its id.
  Future<String> submit() async {
    final s = state;
    final crop = s.crop ?? CropChoice.unknown;
    final flag = ref.read(onDeviceCropGuessEnabledProvider);
    final guess = flag ? _bestGuess(s.accepted) : null;
    final model = s.accepted.isEmpty
        ? null
        : s.accepted.first.quality.modelVersion;
    final id = await ref
        .read(diagnosisRepositoryProvider)
        .submit(
          DiagnosisRequest(
            photos: s.accepted,
            farmerId: s.farmerId,
            cropPlotId: crop.cropPlotId,
            cropId: crop.cropId,
            cropCode: crop.code == 'unknown' ? null : crop.code,
            cropStage: crop.stage,
            cropGuess: guess,
            onDeviceModel: model,
            askExpert: s.askExpert,
            subject: s.subject,
          ),
        );
    state = CaptureState(subject: s.subject, farmerId: s.farmerId);
    return id;
  }
}

/// Capture time of shots (tests pin it).
final Provider<DateTime Function()> captureClockProvider =
    Provider<DateTime Function()>(
      (ref) =>
          () => DateTime.now().toUtc(),
    );

/// The DX-001 photo gate. Defaults to the Laplacian heuristic; the apps
/// override it with `TfliteQualityModel` (which falls back to the heuristic
/// by itself).
final Provider<OnDeviceQualityModel> onDeviceQualityModelProvider =
    Provider<OnDeviceQualityModel>((ref) => PhotoQualityCheck.defaultModel);

/// Shot → processed photo → gate.
final Provider<DiagnosisPhotoPipeline> diagnosisPhotoPipelineProvider =
    Provider<DiagnosisPhotoPipeline>(
      (ref) => DiagnosisPhotoPipeline(
        model: ref.watch(onDeviceQualityModelProvider),
      ),
    );

/// The capture session.
final NotifierProvider<CropDoctorCapture, CaptureState>
cropDoctorCaptureProvider = NotifierProvider<CropDoctorCapture, CaptureState>(
  CropDoctorCapture.new,
);
