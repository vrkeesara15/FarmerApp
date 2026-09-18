import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/open_database.dart';
import '../geo/geo.dart';
import '../photo/photo_processor.dart';
import '../photo/photo_quality.dart';
import '../sync/outbox.dart';
import '../sync/sync_models.dart';
import '../sync/sync_providers.dart';
import 'farm_options.dart';
import 'farmer_repository.dart';
import 'farmers_providers.dart';
import 'location_source.dart';
import 'phone_verify_api.dart';
import 'registration_draft.dart';

/// The A21 wizard steps (A23 uses [boundary] and [crops] only).
enum RegistrationStep {
  /// A21a name, phone + OTP, village, landmark, language, ownership.
  basics,

  /// A21b farm boundary, area, soil, irrigation, photo.
  boundary,

  /// A21c crop plots.
  crops,

  /// A21d consent.
  consent,

  /// A21e review and save.
  review;

  /// Steps of [mode] in order.
  static List<RegistrationStep> stepsFor(DraftMode mode) => switch (mode) {
    DraftMode.newFarmer => RegistrationStep.values,
    DraftMode.farm => const <RegistrationStep>[boundary, crops],
  };
}

/// What blocks a step from completing (mapped to copy by the screens).
enum StepIssue {
  /// Name empty.
  nameRequired,

  /// Not a 10-digit Indian mobile number.
  phoneInvalid,

  /// A local farmer already has the phone (FA-012 duplicate blocked).
  phoneDuplicate,

  /// OTP sent but neither confirmed nor deferred.
  phoneUnverified,

  /// No village chosen (or typed when none synced).
  villageRequired,

  /// No language chosen.
  languageRequired,

  /// Fewer than three boundary points.
  boundaryTooFewPoints,

  /// Boundary crosses itself (VA-F03).
  boundarySelfIntersecting,

  /// No declared acres.
  areaRequired,

  /// No plots, or a plot without a crop.
  cropRequired,

  /// A plot without a sowing date.
  sowingDateRequired,

  /// Data consent not granted.
  consentRequired,
}

/// OTP UI state on A21a.
enum OtpUiState {
  /// Nothing in flight.
  idle,

  /// `send` in flight.
  sending,

  /// `confirm` in flight.
  confirming,
}

/// Why the last OTP call failed (copy on A21a).
enum OtpFailure {
  /// Nothing wrong.
  none,

  /// Invalid number.
  invalidNumber,

  /// Wrong code.
  wrongCode,

  /// Code expired / not found.
  expired,

  /// Locked or rate limited.
  locked,

  /// Offline: offer "verify later".
  network,
}

/// A photo taken but not yet accepted (A21b review card).
@immutable
class PendingPhoto {
  /// Creates the pending photo.
  const PendingPhoto({required this.processed, required this.quality});

  /// NF-004 output.
  final ProcessedPhoto processed;

  /// On-device quality gate.
  final PhotoQualityResult quality;
}

/// State of the wizard.
@immutable
class RegistrationState {
  /// Creates the state.
  const RegistrationState({
    this.draft,
    this.restored = false,
    this.otp = OtpUiState.idle,
    this.otpFailure = OtpFailure.none,
    this.otpAttemptsLeft,
    this.otpRetryAfter,
    this.duplicateOfId,
    this.location,
    this.walking = false,
    this.lastFix,
    this.pendingPhoto,
    this.photoBusy = false,
    this.saving = false,
    this.savedFarmerId,
    this.savedFarmId,
  });

  /// The draft; `null` before [RegistrationNotifier.start].
  final RegistrationDraft? draft;

  /// [RegistrationNotifier.start] has run.
  final bool restored;

  /// OTP request state.
  final OtpUiState otp;

  /// Last OTP failure.
  final OtpFailure otpFailure;

  /// Wrong attempts left (after a wrong code).
  final int? otpAttemptsLeft;

  /// Wait before another code when locked / rate limited.
  final Duration? otpRetryAfter;

  /// Local farmer that already has the phone.
  final String? duplicateOfId;

  /// GPS availability after the last check.
  final LocationAvailability? location;

  /// Walk-around capture running.
  final bool walking;

  /// Latest fix while walking (accuracy indicator).
  final GeoFix? lastFix;

  /// Photo awaiting "Use photo".
  final PendingPhoto? pendingPhoto;

  /// Camera / processing in flight.
  final bool photoBusy;

  /// Save in flight.
  final bool saving;

  /// Set once saved (A21 → A22 navigation).
  final String? savedFarmerId;

  /// Set once a farm was saved on A23.
  final String? savedFarmId;

  /// Copy with overrides.
  RegistrationState copyWith({
    RegistrationDraft? draft,
    bool? restored,
    OtpUiState? otp,
    OtpFailure? otpFailure,
    int? otpAttemptsLeft,
    Duration? otpRetryAfter,
    bool clearOtpHints = false,
    String? duplicateOfId,
    bool clearDuplicate = false,
    LocationAvailability? location,
    bool? walking,
    GeoFix? lastFix,
    PendingPhoto? pendingPhoto,
    bool clearPendingPhoto = false,
    bool? photoBusy,
    bool? saving,
    String? savedFarmerId,
    String? savedFarmId,
  }) => RegistrationState(
    draft: draft ?? this.draft,
    restored: restored ?? this.restored,
    otp: otp ?? this.otp,
    otpFailure: otpFailure ?? this.otpFailure,
    otpAttemptsLeft: clearOtpHints
        ? null
        : (otpAttemptsLeft ?? this.otpAttemptsLeft),
    otpRetryAfter: clearOtpHints ? null : (otpRetryAfter ?? this.otpRetryAfter),
    duplicateOfId: clearDuplicate
        ? null
        : (duplicateOfId ?? this.duplicateOfId),
    location: location ?? this.location,
    walking: walking ?? this.walking,
    lastFix: lastFix ?? this.lastFix,
    pendingPhoto: clearPendingPhoto
        ? null
        : (pendingPhoto ?? this.pendingPhoto),
    photoBusy: photoBusy ?? this.photoBusy,
    saving: saving ?? this.saving,
    savedFarmerId: savedFarmerId ?? this.savedFarmerId,
    savedFarmId: savedFarmId ?? this.savedFarmId,
  );
}

/// Drives A21 (new farmer) and A23 (add / edit farm): draft persisted in
/// `kv` after every change, per-step validation, OTP via
/// [farmerPhoneVerifyApiProvider] with an offline "verify later", walk-around
/// and tap boundary capture, the NF-004 photo pipeline, and a save that
/// queues farmer + farms + crop plots + consents through the [Outbox] in one
/// local transaction (FA-012, FA-013).
class RegistrationNotifier extends Notifier<RegistrationState> {
  StreamSubscription<GeoFix>? _walk;

  /// Minimum distance between two appended walk fixes (GPS jitter filter).
  static const double minFixSpacingMetres = 3;

  @override
  RegistrationState build() {
    ref.onDispose(() => _walk?.cancel());
    return const RegistrationState();
  }

  Outbox get _outbox => ref.read(outboxProvider);
  FarmerRepository get _repo => ref.read(farmerRepositoryProvider);
  DateTime get _now => ref.read(clockProvider)();
  String _newId() => ref.read(idGeneratorProvider)();

  RegistrationDraft get _draft => state.draft!;

  // --- lifecycle ----------------------------------------------------------

  /// Restores the persisted draft when it matches [mode] / [farmerId], or
  /// starts a fresh one. In [DraftMode.farm] with [farmId] the existing farm
  /// and its plots are loaded for editing.
  Future<void> start({
    DraftMode mode = DraftMode.newFarmer,
    String? farmerId,
    String? farmId,
    String? language,
  }) async {
    await _walk?.cancel();
    _walk = null;
    final stored = await _readStored();
    if (stored != null &&
        stored.mode == mode &&
        (mode == DraftMode.newFarmer || stored.farmerId == farmerId) &&
        (farmId == null || stored.farms.any((f) => f.id == farmId))) {
      state = RegistrationState(draft: stored, restored: true);
      return;
    }
    RegistrationDraft draft;
    if (mode == DraftMode.newFarmer) {
      draft = RegistrationDraft(
        farmerId: _newId(),
        language: language,
        farms: <FarmDraft>[FarmDraft(id: _newId())],
      );
    } else {
      FarmDraft farm;
      if (farmId != null) {
        final existing = await _repo.farm(farmId);
        farm = existing == null
            ? FarmDraft(id: _newId())
            : _fromExisting(existing);
      } else {
        farm = FarmDraft(id: _newId());
      }
      draft = RegistrationDraft(
        farmerId: farmerId!,
        mode: DraftMode.farm,
        farms: <FarmDraft>[farm],
      );
    }
    state = RegistrationState(draft: draft, restored: true);
    await _persist();
  }

  FarmDraft _fromExisting(FarmDetail d) => FarmDraft(
    id: d.farm.id,
    name: d.farm.name ?? '',
    boundary: d.boundary,
    mode: BoundaryMode.tap,
    closed: d.boundary.length >= 3,
    declaredAcres: d.farm.areaAcres,
    soil: d.farm.soil,
    irrigation: d.farm.irrigation,
    ownership: d.farm.ownership,
    existing: true,
    version: d.farm.version,
    plots: <CropPlotDraft>[
      for (final p in d.plots)
        CropPlotDraft(
          id: p.id,
          cropId: p.cropId,
          variety: p.variety ?? '',
          sowingDate: p.sowingDate == null
              ? null
              : DateTime.tryParse(p.sowingDate!),
          areaAcres: p.areaAcres,
          existing: true,
        ),
    ],
  );

  Future<RegistrationDraft?> _readStored() async {
    final raw = await ref
        .read(appDatabaseProvider)
        .getValue(RegistrationDraft.kvKey);
    if (raw == null) return null;
    try {
      return RegistrationDraft.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _persist() => ref
      .read(appDatabaseProvider)
      .setValue(RegistrationDraft.kvKey, jsonEncode(_draft.toJson()));

  Future<void> _set(RegistrationDraft draft) async {
    state = state.copyWith(draft: draft.copyWith(updatedAt: _now));
    await _persist();
  }

  Future<void> _setFarm(FarmDraft Function(FarmDraft farm) change) {
    final farms = List<FarmDraft>.of(_draft.farms);
    final i = _draft.currentFarm.clamp(0, farms.length - 1);
    farms[i] = change(farms[i]);
    return _set(_draft.copyWith(farms: farms));
  }

  /// Throws the draft away (kv cleared) and stops any walk.
  Future<void> discard() async {
    await _walk?.cancel();
    _walk = null;
    await ref.read(appDatabaseProvider).removeValue(RegistrationDraft.kvKey);
    state = const RegistrationState(restored: true);
  }

  // --- steps --------------------------------------------------------------

  /// Steps for the current mode.
  List<RegistrationStep> get steps => RegistrationStep.stepsFor(_draft.mode);

  /// Current step.
  RegistrationStep get currentStep =>
      steps[_draft.step.clamp(0, steps.length - 1)];

  /// Issues blocking [step].
  List<StepIssue> issuesFor(RegistrationStep step) {
    final d = _draft;
    final issues = <StepIssue>[];
    switch (step) {
      case RegistrationStep.basics:
        if (d.name.trim().isEmpty) issues.add(StepIssue.nameRequired);
        if (!indianMobilePattern.hasMatch(d.phone)) {
          issues.add(StepIssue.phoneInvalid);
        } else if (state.duplicateOfId != null) {
          issues.add(StepIssue.phoneDuplicate);
        }
        if (d.verification == PhoneVerification.unverified ||
            d.verification == PhoneVerification.sent) {
          issues.add(StepIssue.phoneUnverified);
        }
        if (d.villageId == null && d.villageName.trim().isEmpty) {
          issues.add(StepIssue.villageRequired);
        }
        if (d.language == null) issues.add(StepIssue.languageRequired);
      case RegistrationStep.boundary:
        final farm = d.farm;
        if (farm == null || farm.boundary.length < 3) {
          issues.add(StepIssue.boundaryTooFewPoints);
        } else if (isSelfIntersecting(farm.boundary)) {
          issues.add(StepIssue.boundarySelfIntersecting);
        }
        if (farm == null ||
            farm.declaredAcres == null ||
            farm.declaredAcres! <= 0) {
          issues.add(StepIssue.areaRequired);
        }
      case RegistrationStep.crops:
        final plots = d.farm?.plots ?? const <CropPlotDraft>[];
        if (plots.isEmpty || plots.any((p) => p.cropId == null)) {
          issues.add(StepIssue.cropRequired);
        }
        if (plots.any((p) => p.sowingDate == null)) {
          issues.add(StepIssue.sowingDateRequired);
        }
      case RegistrationStep.consent:
        if (!d.consentData) issues.add(StepIssue.consentRequired);
      case RegistrationStep.review:
        for (final s in steps) {
          if (s != RegistrationStep.review) issues.addAll(issuesFor(s));
        }
    }
    return issues;
  }

  /// Every farm passes the boundary and crops checks (review / save).
  List<StepIssue> issuesForAllFarms() {
    final saved = _draft.currentFarm;
    final issues = <StepIssue>[];
    for (var i = 0; i < _draft.farms.length; i++) {
      state = state.copyWith(draft: _draft.copyWith(currentFarm: i));
      issues
        ..addAll(issuesFor(RegistrationStep.boundary))
        ..addAll(issuesFor(RegistrationStep.crops));
    }
    state = state.copyWith(draft: _draft.copyWith(currentFarm: saved));
    return issues.toSet().toList();
  }

  /// Moves to [step] (no validation; the screens call [next] to validate).
  Future<void> goTo(RegistrationStep step) =>
      _set(_draft.copyWith(step: steps.indexOf(step)));

  /// Validates the current step and advances; returns the blocking issues
  /// (empty when it advanced).
  Future<List<StepIssue>> next() async {
    final issues = issuesFor(currentStep);
    if (issues.isNotEmpty) return issues;
    if (currentStep == RegistrationStep.boundary) await stopWalk();
    final i = _draft.step;
    if (i < steps.length - 1) await _set(_draft.copyWith(step: i + 1));
    return const <StepIssue>[];
  }

  /// Goes one step back (stops a running walk).
  Future<void> back() async {
    if (currentStep == RegistrationStep.boundary) await stopWalk();
    final i = _draft.step;
    if (i > 0) await _set(_draft.copyWith(step: i - 1));
  }

  // --- A21a basics --------------------------------------------------------

  /// Sets the name.
  Future<void> setName(String name) => _set(_draft.copyWith(name: name));

  /// Sets the 10-digit phone; resets verification and re-runs the local
  /// duplicate check.
  Future<void> setPhone(String phone) async {
    if (phone == _draft.phone) return;
    await _set(
      _draft.copyWith(
        phone: phone,
        verification: PhoneVerification.unverified,
        clearVerificationToken: true,
      ),
    );
    state = state.copyWith(
      otp: OtpUiState.idle,
      otpFailure: OtpFailure.none,
      clearOtpHints: true,
    );
    await checkDuplicate();
  }

  /// FA-012: blocks a phone another local farmer already has.
  Future<void> checkDuplicate() async {
    if (!indianMobilePattern.hasMatch(_draft.phone)) {
      state = state.copyWith(clearDuplicate: true);
      return;
    }
    final other = await _repo.findByPhone(
      toE164India(_draft.phone),
      excludingId: _draft.farmerId,
    );
    state = other == null
        ? state.copyWith(clearDuplicate: true)
        : state.copyWith(duplicateOfId: other.id);
  }

  /// Sets the village from the synced list.
  Future<void> setVillage(String? villageId, {String name = ''}) => _set(
    _draft.copyWith(
      villageId: villageId,
      clearVillageId: villageId == null,
      villageName: name,
    ),
  );

  /// Sets a typed village name (no synced villages yet).
  Future<void> setVillageName(String name) =>
      _set(_draft.copyWith(villageName: name, clearVillageId: true));

  /// Sets the landmark.
  Future<void> setLandmark(String landmark) =>
      _set(_draft.copyWith(landmark: landmark));

  /// Sets the preferred language.
  Future<void> setLanguage(String code) =>
      _set(_draft.copyWith(language: code));

  /// Sets land ownership.
  Future<void> setLandOwnership(String value) =>
      _set(_draft.copyWith(landOwnership: value));

  /// Sends the OTP to the farmer (online only; offline reports
  /// [OtpFailure.network] so the screen offers "verify later").
  Future<void> sendOtp() async {
    if (!indianMobilePattern.hasMatch(_draft.phone)) {
      state = state.copyWith(otpFailure: OtpFailure.invalidNumber);
      return;
    }
    if (!await ref.read(connectivityMonitorProvider).isOnline()) {
      state = state.copyWith(otpFailure: OtpFailure.network);
      return;
    }
    state = state.copyWith(
      otp: OtpUiState.sending,
      otpFailure: OtpFailure.none,
      clearOtpHints: true,
    );
    final outcome = await ref
        .read(farmerPhoneVerifyApiProvider)
        .send(toE164India(_draft.phone));
    final failure = switch (outcome.result) {
      PhoneOtpSendResult.sent => OtpFailure.none,
      PhoneOtpSendResult.invalidNumber => OtpFailure.invalidNumber,
      PhoneOtpSendResult.rateLimited ||
      PhoneOtpSendResult.locked => OtpFailure.locked,
      PhoneOtpSendResult.network => OtpFailure.network,
    };
    state = state.copyWith(
      otp: OtpUiState.idle,
      otpFailure: failure,
      otpRetryAfter: outcome.resendAfter,
    );
    if (failure == OtpFailure.none) {
      await _set(_draft.copyWith(verification: PhoneVerification.sent));
    }
  }

  /// Confirms the code; on success the farmer is verified and the token is
  /// kept with its expiry for the create payload.
  Future<void> confirmOtp(String code) async {
    state = state.copyWith(
      otp: OtpUiState.confirming,
      otpFailure: OtpFailure.none,
      clearOtpHints: true,
    );
    final outcome = await ref
        .read(farmerPhoneVerifyApiProvider)
        .confirm(toE164India(_draft.phone), code);
    final failure = switch (outcome.result) {
      PhoneOtpConfirmResult.ok => OtpFailure.none,
      PhoneOtpConfirmResult.invalid => OtpFailure.wrongCode,
      PhoneOtpConfirmResult.expired ||
      PhoneOtpConfirmResult.notFound => OtpFailure.expired,
      PhoneOtpConfirmResult.locked => OtpFailure.locked,
      PhoneOtpConfirmResult.network => OtpFailure.network,
    };
    state = state.copyWith(
      otp: OtpUiState.idle,
      otpFailure: failure,
      otpAttemptsLeft: outcome.attemptsLeft,
      otpRetryAfter: outcome.retryAfter,
    );
    if (failure == OtpFailure.none) {
      await _set(
        _draft.copyWith(
          verification: PhoneVerification.verified,
          verificationToken: outcome.token,
          verificationExpiresAt: _now.add(
            outcome.expiresIn ?? const Duration(minutes: 30),
          ),
        ),
      );
    }
  }

  /// Offline (or no signal at the farm): save unverified, verify from A22.
  Future<void> verifyLater() async {
    state = state.copyWith(otpFailure: OtpFailure.none, clearOtpHints: true);
    await _set(
      _draft.copyWith(
        verification: PhoneVerification.verifyLater,
        clearVerificationToken: true,
      ),
    );
  }

  // --- A21b boundary ------------------------------------------------------

  /// Switches walk / tap capture (keeps the points).
  Future<void> setBoundaryMode(BoundaryMode mode) async {
    if (mode == BoundaryMode.tap) await stopWalk();
    await _setFarm((f) => f.copyWith(mode: mode));
  }

  /// Sets the farm label.
  Future<void> setFarmName(String name) =>
      _setFarm((f) => f.copyWith(name: name));

  /// Starts appending GPS fixes (FA-010: only on this explicit action).
  Future<void> startWalk() async {
    final source = ref.read(locationSourceProvider);
    final availability = await source.ensureAvailable();
    state = state.copyWith(location: availability);
    if (availability != LocationAvailability.available) return;
    await _setFarm((f) => f.copyWith(mode: BoundaryMode.walk, closed: false));
    await _walk?.cancel();
    _walk = source.watch().listen((fix) => unawaited(appendFix(fix)));
    state = state.copyWith(walking: true);
    final now = await source.current();
    if (now != null) state = state.copyWith(lastFix: now);
  }

  /// Stops listening to GPS.
  Future<void> stopWalk() async {
    await _walk?.cancel();
    _walk = null;
    if (state.walking) state = state.copyWith(walking: false);
  }

  /// Appends a walk fix (skipped when closer than [minFixSpacingMetres] to
  /// the last point).
  Future<void> appendFix(GeoFix fix) async {
    state = state.copyWith(lastFix: fix);
    final farm = _draft.farm;
    if (farm == null || farm.closed || !state.walking) return;
    if (farm.boundary.isNotEmpty &&
        distanceMetres(farm.boundary.last, fix.point) < minFixSpacingMetres) {
      return;
    }
    await _setFarm(
      (f) => f.copyWith(boundary: <GeoPoint>[...f.boundary, fix.point]),
    );
  }

  /// Closes the walked polygon and stops GPS.
  Future<void> closePolygon() async {
    await stopWalk();
    await _setFarm((f) => f.copyWith(closed: true));
  }

  /// Tap mode: adds a corner.
  Future<void> addCorner(GeoPoint point) => _setFarm(
    (f) => f.copyWith(
      mode: BoundaryMode.tap,
      boundary: <GeoPoint>[...f.boundary, point],
      closed: f.boundary.length + 1 >= 3,
    ),
  );

  /// Removes the last point.
  Future<void> undoPoint() => _setFarm(
    (f) => f.boundary.isEmpty
        ? f
        : f.copyWith(
            boundary: f.boundary.sublist(0, f.boundary.length - 1),
            closed: false,
          ),
  );

  /// Clears every point.
  Future<void> clearBoundary() async {
    await stopWalk();
    await _setFarm(
      (f) => f.copyWith(boundary: const <GeoPoint>[], closed: false),
    );
  }

  /// Sets the declared area (`null` clears it).
  Future<void> setDeclaredAcres(double? acres) => _setFarm(
    (f) => f.copyWith(declaredAcres: acres, clearDeclaredAcres: acres == null),
  );

  /// Copies the computed area into the declared field.
  Future<void> useComputedAcres() => _setFarm(
    (f) => f.copyWith(
      declaredAcres: double.parse(f.computedAcres.toStringAsFixed(2)),
    ),
  );

  /// Sets the soil type.
  Future<void> setSoil(String soil) => _setFarm((f) => f.copyWith(soil: soil));

  /// Sets the irrigation type.
  Future<void> setIrrigation(String value) =>
      _setFarm((f) => f.copyWith(irrigation: value));

  /// Sets the farm ownership.
  Future<void> setFarmOwnership(String value) =>
      _setFarm((f) => f.copyWith(ownership: value));

  /// Opens the camera (never the gallery), runs the NF-004 pipeline and the
  /// quality gate, and parks the result for review.
  Future<void> takePhoto() async {
    state = state.copyWith(photoBusy: true, clearPendingPhoto: true);
    try {
      final bytes = await ref.read(cameraSourceProvider).capture();
      if (bytes == null) return;
      final fix = state.lastFix;
      final processed = await PhotoProcessor.process(
        bytes,
        captureTime: _now,
        location: fix == null
            ? null
            : PhotoLocation(
                latitude: fix.point.latitude,
                longitude: fix.point.longitude,
                accuracyMetres: fix.accuracyMetres,
              ),
      );
      final quality = await PhotoQualityCheck.evaluate(processed.bytes);
      state = state.copyWith(
        pendingPhoto: PendingPhoto(processed: processed, quality: quality),
      );
    } on PhotoDecodeException {
      state = state.copyWith(clearPendingPhoto: true);
    } finally {
      state = state.copyWith(photoBusy: false);
    }
  }

  /// Accepts the pending photo: saved to disk and queued as a resumable
  /// upload the farm op will wait for.
  Future<void> usePhoto() async {
    final pending = state.pendingPhoto;
    if (pending == null) return;
    final farm = _draft.farm!;
    final n = farm.photos.length + 1;
    final path = await ref
        .read(photoStoreProvider)
        .save('farm_${farm.id}_$n.jpg', pending.processed.bytes);
    final uploadId = await _outbox.enqueueUpload(
      filePath: path,
      bytes: Uint8List.fromList(pending.processed.bytes),
      purpose: 'farm_photo',
    );
    await _setFarm(
      (f) => f.copyWith(
        photos: <DraftPhoto>[
          ...f.photos,
          DraftPhoto(
            uploadId: uploadId,
            filePath: path,
            sizeBytes: pending.processed.bytes.length,
            width: pending.processed.width,
            height: pending.processed.height,
          ),
        ],
      ),
    );
    state = state.copyWith(clearPendingPhoto: true);
  }

  /// Drops the pending photo (the screen opens the camera again).
  void retakePhoto() => state = state.copyWith(clearPendingPhoto: true);

  /// Removes an accepted photo from the farm.
  Future<void> removePhoto(String uploadId) => _setFarm(
    (f) => f.copyWith(
      photos: f.photos.where((p) => p.uploadId != uploadId).toList(),
    ),
  );

  // --- farms (FA-013) -----------------------------------------------------

  /// Adds another farm and jumps to its boundary step.
  Future<void> addFarm() async {
    await stopWalk();
    final farms = <FarmDraft>[..._draft.farms, FarmDraft(id: _newId())];
    await _set(
      _draft.copyWith(
        farms: farms,
        currentFarm: farms.length - 1,
        step: steps.indexOf(RegistrationStep.boundary),
      ),
    );
  }

  /// Makes farm [index] the one the boundary / crops steps edit.
  Future<void> selectFarm(int index, {RegistrationStep? step}) async {
    await stopWalk();
    await _set(
      _draft.copyWith(
        currentFarm: index.clamp(0, _draft.farms.length - 1),
        step: step == null ? null : steps.indexOf(step),
      ),
    );
  }

  /// Removes farm [index] (never the last one).
  Future<void> removeFarm(int index) async {
    if (_draft.farms.length <= 1) return;
    final farms = List<FarmDraft>.of(_draft.farms)..removeAt(index);
    await _set(
      _draft.copyWith(
        farms: farms,
        currentFarm: _draft.currentFarm.clamp(0, farms.length - 1),
      ),
    );
  }

  // --- A21c crops ---------------------------------------------------------

  /// Adds an empty plot to the current farm.
  Future<void> addPlot() => _setFarm(
    (f) => f.copyWith(
      plots: <CropPlotDraft>[
        ...f.plots,
        CropPlotDraft(id: _newId()),
      ],
    ),
  );

  /// Updates plot [plotId] of the current farm.
  Future<void> updatePlot(
    String plotId, {
    String? cropId,
    String? variety,
    DateTime? sowingDate,
    double? areaAcres,
    bool clearArea = false,
  }) => _setFarm(
    (f) => f.copyWith(
      plots: <CropPlotDraft>[
        for (final p in f.plots)
          if (p.id == plotId)
            p.copyWith(
              cropId: cropId,
              variety: variety,
              sowingDate: sowingDate,
              areaAcres: areaAcres,
              clearArea: clearArea,
            )
          else
            p,
      ],
    ),
  );

  /// Removes a plot (an existing one is deleted on save).
  Future<void> removePlot(String plotId) => _setFarm((f) {
    final removed = f.plots.where((p) => p.id == plotId).firstOrNull;
    return f.copyWith(
      plots: f.plots.where((p) => p.id != plotId).toList(),
      removedPlotIds: removed != null && removed.existing
          ? <String>[...f.removedPlotIds, plotId]
          : f.removedPlotIds,
    );
  });

  // --- A21d consent -------------------------------------------------------

  /// Required data consent.
  Future<void> setConsentData({required bool granted}) =>
      _set(_draft.copyWith(consentData: granted));

  /// Optional marketing consent.
  Future<void> setConsentMarketing({required bool granted}) =>
      _set(_draft.copyWith(consentMarketing: granted));

  // --- A21e save ----------------------------------------------------------

  /// Farmer create payload (wire shape of `FarmerCreate` plus the local
  /// cache fields the sync tables keep).
  Map<String, Object?> farmerPayload() {
    final d = _draft;
    final verified = d.isVerifiedAt(_now);
    return <String, Object?>{
      'phone': toE164India(d.phone),
      'name': d.name.trim(),
      'village_id': d.villageId,
      if (d.villageId == null) 'village_name': d.villageName.trim(),
      'landmark': d.landmark.trim().isEmpty ? null : d.landmark.trim(),
      'language': d.language,
      'preferred_language': d.language,
      'land_ownership': d.landOwnership,
      'source': 'field_officer',
      'phone_verified': verified,
      'consent_marketing': d.consentMarketing,
      if (verified) ...<String, Object?>{
        phoneVerificationTokenKey: d.verificationToken,
        phoneVerificationExpiresKey: d.verificationExpiresAt!
            .toUtc()
            .toIso8601String(),
      },
    };
  }

  /// Farm create / update payload (`FarmCreate` shape; photos as
  /// `upload:<id>` placeholders the engine resolves).
  Map<String, Object?> farmPayload(FarmDraft f) => <String, Object?>{
    'farmer_id': _draft.farmerId,
    'name': f.name.trim().isEmpty ? null : f.name.trim(),
    'boundary': f.boundary.length >= 3 ? polygonToGeoJson(f.boundary) : null,
    'area_acres': f.declaredAcres,
    'soil': f.soil,
    'irrigation': f.irrigation,
    'ownership': f.ownership ?? _draft.landOwnership,
    'photos': <String>[for (final p in f.photos) Outbox.uploadRef(p.uploadId)],
  };

  /// Crop plot payload (`CropPlotCreate` shape).
  Map<String, Object?> plotPayload(FarmDraft farm, CropPlotDraft p) =>
      <String, Object?>{
        'farm_id': farm.id,
        'crop_id': p.cropId,
        'variety': p.variety.trim().isEmpty ? null : p.variety.trim(),
        'season': p.season,
        'sowing_date': p.sowingDate?.toIso8601String().substring(0, 10),
        'area_acres': p.areaAcres,
      };

  Map<String, Object?> _consentPayload(
    String purpose, {
    required bool granted,
  }) => <String, Object?>{
    'farmer_id': _draft.farmerId,
    'purpose': purpose,
    'granted': granted,
    'language': _draft.language,
    'channel': 'officer',
  };

  /// Validates everything and queues the ops in push order inside one
  /// local transaction: farmer, then per farm the farm and its plots, then
  /// the consent records. Returns the blocking issues (empty on success);
  /// on success the draft is cleared and [RegistrationState.savedFarmerId]
  /// (and [RegistrationState.savedFarmId] on A23) is set.
  Future<List<StepIssue>> save() async {
    final d = _draft;
    final issues = <StepIssue>{
      if (d.mode == DraftMode.newFarmer) ...issuesFor(RegistrationStep.basics),
      ...issuesForAllFarms(),
      if (d.mode == DraftMode.newFarmer) ...issuesFor(RegistrationStep.consent),
    }.toList();
    if (issues.isNotEmpty) return issues;
    await stopWalk();
    state = state.copyWith(saving: true);
    try {
      await _outbox.store.db.transaction(() async {
        if (d.mode == DraftMode.newFarmer) {
          await _outbox.enqueueCreate(
            SyncEntities.farmer,
            d.farmerId,
            farmerPayload(),
          );
        }
        for (final farm in d.farms) {
          if (farm.existing) {
            await _outbox.enqueueUpdate(
              SyncEntities.farm,
              farm.id,
              farmPayload(farm),
            );
          } else {
            await _outbox.enqueueCreate(
              SyncEntities.farm,
              farm.id,
              farmPayload(farm),
            );
          }
          for (final plot in farm.plots) {
            if (plot.existing) {
              await _outbox.enqueueUpdate(
                SyncEntities.cropPlot,
                plot.id,
                plotPayload(farm, plot),
              );
            } else {
              await _outbox.enqueueCreate(
                SyncEntities.cropPlot,
                plot.id,
                plotPayload(farm, plot),
              );
            }
          }
          for (final removed in farm.removedPlotIds) {
            await _outbox.enqueueDelete(SyncEntities.cropPlot, removed);
          }
        }
        if (d.mode == DraftMode.newFarmer) {
          await _outbox.enqueueCreate(
            SyncEntities.consentRecord,
            _newId(),
            _consentPayload('data', granted: true),
          );
          await _outbox.enqueueCreate(
            SyncEntities.consentRecord,
            _newId(),
            _consentPayload('marketing', granted: d.consentMarketing),
          );
        }
        await ref
            .read(appDatabaseProvider)
            .removeValue(RegistrationDraft.kvKey);
      });
    } finally {
      state = state.copyWith(saving: false);
    }
    state = state.copyWith(
      savedFarmerId: d.farmerId,
      savedFarmId: d.mode == DraftMode.farm ? d.farms.first.id : null,
    );
    return const <StepIssue>[];
  }
}

/// Convenience for tests and screens: issues as a stable list.
bool sameIssues(List<StepIssue> a, List<StepIssue> b) => listEquals(a, b);
