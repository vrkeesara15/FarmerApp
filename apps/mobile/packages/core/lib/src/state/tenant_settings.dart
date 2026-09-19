import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import '../catalog/rest_json_client.dart';
import '../db/app_database.dart';
import '../duty/duty_models.dart';
import '../visits/visit_models.dart';

/// The tenant settings the apps cache (`GET /v1/settings/public`, WC-012):
/// geofence and meeting-point radius, minimum visit time, duty auto end,
/// sampling intervals, languages and branding. Missing or invalid values
/// keep the SPEC defaults, which also apply until the first pull.
@immutable
class PublicTenantSettings {
  /// Creates the settings (defaults = SPEC / `TenantSettings` defaults).
  const PublicTenantSettings({
    this.geofenceRadiusM = 150,
    this.meetingPointRadiusM,
    this.minVisitDurationS = 300,
    this.autoDutyEndLocalTime = '20:00',
    this.idleEndMinutes = 60,
    this.locationPolicyVersion,
    this.samplingMovingS = 120,
    this.samplingStationaryS = 600,
    this.samplingUploadS = 900,
    this.languagesEnabled = const <String>['en', 'te', 'kn', 'hi', 'mr'],
    this.defaultLanguage = 'en',
    this.branding = const TenantBranding(),
  });

  /// Parses the API shape leniently.
  factory PublicTenantSettings.fromJson(Map<String, Object?> json) {
    const d = PublicTenantSettings();
    int positive(Object? v, int fallback) =>
        v is num && v > 0 ? v.toInt() : fallback;
    final sampling = json['sampling'] is Map
        ? Map<String, Object?>.from(json['sampling']! as Map)
        : const <String, Object?>{};
    final meeting = json['meeting_point_radius_m'];
    final end = json['auto_duty_end_local_time'];
    final languages = json['languages_enabled'];
    final brandingJson = json['branding'];
    return PublicTenantSettings(
      geofenceRadiusM: positive(json['geofence_radius_m'], d.geofenceRadiusM),
      meetingPointRadiusM: meeting is num && meeting > 0
          ? meeting.toInt()
          : null,
      minVisitDurationS:
          json['min_visit_duration_s'] is num &&
              (json['min_visit_duration_s']! as num) >= 0
          ? (json['min_visit_duration_s']! as num).toInt()
          : d.minVisitDurationS,
      autoDutyEndLocalTime:
          end is String && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(end)
          ? end
          : d.autoDutyEndLocalTime,
      idleEndMinutes: positive(json['idle_end_minutes'], d.idleEndMinutes),
      locationPolicyVersion: json['location_policy_version'] as String?,
      samplingMovingS: positive(sampling['moving_s'], d.samplingMovingS),
      samplingStationaryS: positive(
        sampling['stationary_s'],
        d.samplingStationaryS,
      ),
      samplingUploadS: positive(sampling['upload_s'], d.samplingUploadS),
      languagesEnabled: languages is List && languages.isNotEmpty
          ? <String>[for (final l in languages) '$l']
          : d.languagesEnabled,
      defaultLanguage:
          (json['default_language'] as String?) ?? d.defaultLanguage,
      branding: brandingJson is Map
          ? TenantBranding.fromJson(Map<String, Object?>.from(brandingJson))
          : d.branding,
    );
  }

  /// VV-003 farm polygon buffer (m).
  final int geofenceRadiusM;

  /// Default meeting-point radius (m); null = [geofenceRadiusM].
  final int? meetingPointRadiusM;

  /// FA-017 minimum visit duration (s).
  final int minVisitDurationS;

  /// VV-007 duty auto end, `HH:MM` IST.
  final String autoDutyEndLocalTime;

  /// VV-007 idle end (min; enforced server-side).
  final int idleEndMinutes;

  /// FA-011 current location policy version.
  final String? locationPolicyVersion;

  /// VV-001 moving sampling interval (s).
  final int samplingMovingS;

  /// VV-001 stationary sampling interval (s).
  final int samplingStationaryS;

  /// VV-001 batch upload interval (s).
  final int samplingUploadS;

  /// NF-008 languages offered.
  final List<String> languagesEnabled;

  /// Language of a new user.
  final String defaultLanguage;

  /// App names, colour, logo, support phone.
  final TenantBranding branding;

  /// The visit flow's view (pre-check radius, proof checklist minimum).
  VisitSettings get visitSettings => VisitSettings(
    geofenceRadiusM: geofenceRadiusM.toDouble(),
    minVisitDurationS: minVisitDurationS,
    meetingPointRadiusM: meetingPointRadiusM?.toDouble(),
  );

  /// [base] (the cached `GET /v1/duty/policy`) with this tenant's sampling
  /// cadence and auto-end time.
  DutyPolicy applyTo(DutyPolicy base) => DutyPolicy(
    movingInterval: Duration(seconds: samplingMovingS),
    stationaryInterval: Duration(seconds: samplingStationaryS),
    uploadInterval: Duration(seconds: samplingUploadS),
    uploadOnWifiOrCharging: base.uploadOnWifiOrCharging,
    autoEndLocalTime: autoDutyEndLocalTime,
    utcOffset: base.utcOffset,
  );

  /// Wire shape (the cache in `kv`).
  Map<String, Object?> toJson() => <String, Object?>{
    'geofence_radius_m': geofenceRadiusM,
    'meeting_point_radius_m': meetingPointRadiusM,
    'min_visit_duration_s': minVisitDurationS,
    'auto_duty_end_local_time': autoDutyEndLocalTime,
    'idle_end_minutes': idleEndMinutes,
    'location_policy_version': locationPolicyVersion,
    'sampling': <String, Object?>{
      'moving_s': samplingMovingS,
      'stationary_s': samplingStationaryS,
      'upload_s': samplingUploadS,
    },
    'languages_enabled': languagesEnabled,
    'default_language': defaultLanguage,
    'branding': branding.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is PublicTenantSettings &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// `tenant.branding` (C102).
@immutable
class TenantBranding {
  /// Creates the branding.
  const TenantBranding({
    this.appNameAgent,
    this.appNameFarmer,
    this.primaryColour = '#1F6B3A',
    this.logoBlobUri,
    this.supportPhone,
  });

  /// Parses the API shape.
  factory TenantBranding.fromJson(Map<String, Object?> json) {
    final colour = json['primary_colour'];
    return TenantBranding(
      appNameAgent: json['app_name_agent'] as String?,
      appNameFarmer: json['app_name_farmer'] as String?,
      primaryColour:
          colour is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(colour)
          ? colour
          : '#1F6B3A',
      logoBlobUri: json['logo_blob_uri'] as String?,
      supportPhone: json['support_phone'] as String?,
    );
  }

  /// Officer app name override (null: "Mitra").
  final String? appNameAgent;

  /// Farmer app name override (null: "Kisan").
  final String? appNameFarmer;

  /// `#RRGGBB`.
  final String primaryColour;

  /// Logo blob URI.
  final String? logoBlobUri;

  /// Support phone shown in both apps.
  final String? supportPhone;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'app_name_agent': appNameAgent,
    'app_name_farmer': appNameFarmer,
    'primary_colour': primaryColour,
    'logo_blob_uri': logoBlobUri,
    'support_phone': supportPhone,
  };

  @override
  bool operator ==(Object other) =>
      other is TenantBranding &&
      other.appNameAgent == appNameAgent &&
      other.appNameFarmer == appNameFarmer &&
      other.primaryColour == primaryColour &&
      other.logoBlobUri == logoBlobUri &&
      other.supportPhone == supportPhone;

  @override
  int get hashCode => Object.hash(
    appNameAgent,
    appNameFarmer,
    primaryColour,
    logoBlobUri,
    supportPhone,
  );
}

/// Reads `GET /v1/settings/public`.
abstract interface class TenantSettingsApi {
  /// The settings, or `null` when the request did not complete.
  Future<PublicTenantSettings?> fetch();
}

/// Scriptable API for tests.
class FakeTenantSettingsApi implements TenantSettingsApi {
  /// Creates the fake.
  FakeTenantSettingsApi({this.settings});

  /// What [fetch] answers (null = offline).
  PublicTenantSettings? settings;

  /// Calls so far.
  int calls = 0;

  @override
  Future<PublicTenantSettings?> fetch() async {
    calls += 1;
    return settings;
  }
}

/// [TenantSettingsApi] over [RestJsonClient].
class HttpTenantSettingsApi implements TenantSettingsApi {
  /// Creates the client.
  HttpTenantSettingsApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<PublicTenantSettings?> fetch() async {
    final response = await _rest.get('/v1/settings/public');
    return response.ok ? PublicTenantSettings.fromJson(response.body) : null;
  }
}

/// Keeps the pulled settings in `kv` and fans them out to the caches the
/// visit flow ([VisitSettings.kvKey]) and the duty controller
/// (`duty.policy`) read.
class TenantSettingsSync {
  /// Creates the sync.
  TenantSettingsSync({
    required this.db,
    required this.api,
    DateTime Function()? clock,
    this.maxAge = const Duration(hours: 24),
    this.onApplied,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  /// `kv` key of the raw settings.
  static const String kvKey = 'tenant.settings.public';

  /// `kv` key of the last successful pull (UTC ISO 8601).
  static const String fetchedAtKey = 'tenant.settings.fetched_at';

  /// `kv` key of the duty policy cache (same as `LocationPolicyController`).
  static const String dutyPolicyKey = 'duty.policy';

  /// The database.
  final AppDatabase db;

  /// The API.
  final TenantSettingsApi api;

  /// Pull again when the last pull is older than this ("daily").
  final Duration maxAge;

  /// Called after new settings were stored (providers refresh).
  final void Function(PublicTenantSettings settings)? onApplied;

  final DateTime Function() _clock;
  Future<PublicTenantSettings?>? _inFlight;

  /// The cached settings, or the defaults when never pulled.
  Future<PublicTenantSettings> cached() async {
    final raw = await db.getValue(kvKey);
    if (raw == null) return const PublicTenantSettings();
    try {
      return PublicTenantSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return const PublicTenantSettings();
    }
  }

  /// When the last pull succeeded, if ever.
  Future<DateTime?> fetchedAt() async {
    final raw = await db.getValue(fetchedAtKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  /// Pulls now (after login); `null` when offline (the cache stays).
  Future<PublicTenantSettings?> pull() =>
      _inFlight ??= _pull().whenComplete(() => _inFlight = null);

  /// Pulls when never pulled or older than [maxAge] (app start, back
  /// online); returns whether a pull succeeded.
  Future<bool> pullIfStale() async {
    final at = await fetchedAt();
    if (at != null && _clock().difference(at) < maxAge) return false;
    return await pull() != null;
  }

  Future<PublicTenantSettings?> _pull() async {
    final settings = await api.fetch();
    if (settings == null) return null;
    await apply(settings);
    return settings;
  }

  /// Stores [settings] and updates the derived caches.
  Future<void> apply(PublicTenantSettings settings) async {
    await db.setValue(kvKey, jsonEncode(settings.toJson()));
    await db.setValue(
      VisitSettings.kvKey,
      jsonEncode(settings.visitSettings.toJson()),
    );
    var duty = const DutyPolicy();
    final rawDuty = await db.getValue(dutyPolicyKey);
    if (rawDuty != null) {
      try {
        duty = DutyPolicy.fromJson(
          Map<String, Object?>.from(jsonDecode(rawDuty) as Map),
        );
      } on Object {
        // Corrupt cache: rebuild from the defaults.
      }
    }
    await db.setValue(
      dutyPolicyKey,
      jsonEncode(settings.applyTo(duty).toJson()),
    );
    await db.setValue(fetchedAtKey, _clock().toIso8601String());
    onApplied?.call(settings);
  }
}
