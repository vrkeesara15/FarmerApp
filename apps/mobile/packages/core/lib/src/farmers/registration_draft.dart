import 'package:flutter/foundation.dart' show immutable;

import '../geo/geo.dart';
import 'farm_options.dart';

/// How the phone number of the farmer being registered was verified.
enum PhoneVerification {
  /// Nothing sent yet.
  unverified,

  /// OTP sent; waiting for the code.
  sent,

  /// OTP confirmed; a `phone_verification_token` is held.
  verified,

  /// Offline (or the farmer had no signal): saved unverified, to verify
  /// later from A22.
  verifyLater,
}

/// How the boundary of a farm was captured.
enum BoundaryMode {
  /// GPS fixes appended while the officer walks the edge.
  walk,

  /// Four (or more) corners tapped on the map.
  tap,
}

/// A farm photo processed through the NF-004 pipeline and queued for upload.
@immutable
class DraftPhoto {
  /// Creates the photo.
  const DraftPhoto({
    required this.uploadId,
    required this.filePath,
    required this.sizeBytes,
    required this.width,
    required this.height,
  });

  /// Parses the stored shape.
  factory DraftPhoto.fromJson(Map<String, Object?> json) => DraftPhoto(
    uploadId: json['upload_id']! as String,
    filePath: json['file_path']! as String,
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
  );

  /// Local upload id (`uploads.id`); the farm payload carries
  /// `upload:<uploadId>` until the blob URI is known.
  final String uploadId;

  /// Processed JPEG on disk.
  final String filePath;

  /// Encoded size.
  final int sizeBytes;

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// Stored shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'upload_id': uploadId,
    'file_path': filePath,
    'size_bytes': sizeBytes,
    'width': width,
    'height': height,
  };
}

/// One crop plot row of the A21c step.
@immutable
class CropPlotDraft {
  /// Creates the plot.
  const CropPlotDraft({
    required this.id,
    this.cropId,
    this.variety = '',
    this.sowingDate,
    this.areaAcres,
    this.existing = false,
  });

  /// Parses the stored shape.
  factory CropPlotDraft.fromJson(Map<String, Object?> json) => CropPlotDraft(
    id: json['id']! as String,
    cropId: json['crop_id'] as String?,
    variety: (json['variety'] as String?) ?? '',
    sowingDate: json['sowing_date'] is String
        ? DateTime.tryParse(json['sowing_date']! as String)
        : null,
    areaAcres: (json['area_acres'] as num?)?.toDouble(),
    existing: json['existing'] == true,
  );

  /// Client-generated uuid (`crop_plot.id`).
  final String id;

  /// Crop reference id.
  final String? cropId;

  /// Variety as typed.
  final String variety;

  /// Sowing date (date only).
  final DateTime? sowingDate;

  /// Optional plot area.
  final double? areaAcres;

  /// The plot already exists on the server (A23 edit): save is an update.
  final bool existing;

  /// Season derived from [sowingDate].
  String? get season =>
      sowingDate == null ? null : Seasons.forDate(sowingDate!);

  /// Crop and sowing date are set.
  bool get isComplete => cropId != null && sowingDate != null;

  /// Copy with overrides (`clearArea` removes the area).
  CropPlotDraft copyWith({
    String? cropId,
    String? variety,
    DateTime? sowingDate,
    double? areaAcres,
    bool clearArea = false,
    bool? existing,
  }) => CropPlotDraft(
    id: id,
    cropId: cropId ?? this.cropId,
    variety: variety ?? this.variety,
    sowingDate: sowingDate ?? this.sowingDate,
    areaAcres: clearArea ? null : (areaAcres ?? this.areaAcres),
    existing: existing ?? this.existing,
  );

  /// Stored shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'crop_id': cropId,
    'variety': variety,
    'sowing_date': sowingDate?.toIso8601String(),
    'area_acres': areaAcres,
    'existing': existing,
  };
}

/// One farm of the wizard (A21b + A21c), or the farm being edited on A23.
@immutable
class FarmDraft {
  /// Creates the farm.
  const FarmDraft({
    required this.id,
    this.name = '',
    this.boundary = const <GeoPoint>[],
    this.mode = BoundaryMode.walk,
    this.closed = false,
    this.declaredAcres,
    this.soil,
    this.irrigation,
    this.ownership,
    this.photos = const <DraftPhoto>[],
    this.plots = const <CropPlotDraft>[],
    this.existing = false,
    this.removedPlotIds = const <String>[],
    this.version = 0,
  });

  /// Parses the stored shape.
  factory FarmDraft.fromJson(Map<String, Object?> json) => FarmDraft(
    id: json['id']! as String,
    name: (json['name'] as String?) ?? '',
    boundary: <GeoPoint>[
      for (final p in (json['boundary'] as List<Object?>?) ?? const [])
        GeoPoint.fromJson(Map<String, Object?>.from(p! as Map)),
    ],
    mode: BoundaryMode.values.byName((json['mode'] as String?) ?? 'walk'),
    closed: json['closed'] == true,
    declaredAcres: (json['declared_acres'] as num?)?.toDouble(),
    soil: json['soil'] as String?,
    irrigation: json['irrigation'] as String?,
    ownership: json['ownership'] as String?,
    photos: <DraftPhoto>[
      for (final p in (json['photos'] as List<Object?>?) ?? const [])
        DraftPhoto.fromJson(Map<String, Object?>.from(p! as Map)),
    ],
    plots: <CropPlotDraft>[
      for (final p in (json['plots'] as List<Object?>?) ?? const [])
        CropPlotDraft.fromJson(Map<String, Object?>.from(p! as Map)),
    ],
    existing: json['existing'] == true,
    removedPlotIds: <String>[
      for (final id in (json['removed_plot_ids'] as List<Object?>?) ?? const [])
        id! as String,
    ],
    version: (json['version'] as num?)?.toInt() ?? 0,
  );

  /// Client-generated uuid (`farm.id`).
  final String id;

  /// Optional label ("Home farm").
  final String name;

  /// Boundary ring (no closing point).
  final List<GeoPoint> boundary;

  /// How the boundary was captured.
  final BoundaryMode mode;

  /// The officer closed the polygon (walk mode).
  final bool closed;

  /// Acres as declared by the farmer / officer.
  final double? declaredAcres;

  /// Soil type.
  final String? soil;

  /// Irrigation type.
  final String? irrigation;

  /// `own` | `leased`.
  final String? ownership;

  /// Queued photos.
  final List<DraftPhoto> photos;

  /// Crop plots on this farm.
  final List<CropPlotDraft> plots;

  /// The farm already exists on the server (A23 edit).
  final bool existing;

  /// Plots deleted while editing an existing farm.
  final List<String> removedPlotIds;

  /// Server version of an existing farm.
  final int version;

  /// Acres computed from [boundary] (0 with fewer than three points).
  double get computedAcres => polygonAreaAcres(boundary);

  /// The boundary is a usable polygon.
  bool get hasPolygon => boundary.length >= 3 && !isSelfIntersecting(boundary);

  /// VA-F03: declared and computed acres differ by more than 30 %.
  bool get areaMismatch =>
      declaredAcres != null &&
      boundary.length >= 3 &&
      areaDiffersBeyondTolerance(declaredAcres!, computedAcres);

  /// Copy with overrides (`clearDeclaredAcres` removes the value).
  FarmDraft copyWith({
    String? name,
    List<GeoPoint>? boundary,
    BoundaryMode? mode,
    bool? closed,
    double? declaredAcres,
    bool clearDeclaredAcres = false,
    String? soil,
    String? irrigation,
    String? ownership,
    List<DraftPhoto>? photos,
    List<CropPlotDraft>? plots,
    bool? existing,
    List<String>? removedPlotIds,
    int? version,
  }) => FarmDraft(
    id: id,
    name: name ?? this.name,
    boundary: boundary ?? this.boundary,
    mode: mode ?? this.mode,
    closed: closed ?? this.closed,
    declaredAcres: clearDeclaredAcres
        ? null
        : (declaredAcres ?? this.declaredAcres),
    soil: soil ?? this.soil,
    irrigation: irrigation ?? this.irrigation,
    ownership: ownership ?? this.ownership,
    photos: photos ?? this.photos,
    plots: plots ?? this.plots,
    existing: existing ?? this.existing,
    removedPlotIds: removedPlotIds ?? this.removedPlotIds,
    version: version ?? this.version,
  );

  /// Stored shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'boundary': <Object?>[for (final p in boundary) p.toJson()],
    'mode': mode.name,
    'closed': closed,
    'declared_acres': declaredAcres,
    'soil': soil,
    'irrigation': irrigation,
    'ownership': ownership,
    'photos': <Object?>[for (final p in photos) p.toJson()],
    'plots': <Object?>[for (final p in plots) p.toJson()],
    'existing': existing,
    'removed_plot_ids': removedPlotIds,
    'version': version,
  };
}

/// What the draft is for.
enum DraftMode {
  /// A21: a new farmer with one or more farms.
  newFarmer,

  /// A23: a farm added to (or edited on) an existing farmer.
  farm,
}

/// The whole A21 wizard state, persisted to the `kv` table after every
/// change so an interrupted registration resumes where it stopped.
@immutable
class RegistrationDraft {
  /// Creates the draft.
  const RegistrationDraft({
    required this.farmerId,
    this.mode = DraftMode.newFarmer,
    this.step = 0,
    this.name = '',
    this.phone = '',
    this.verification = PhoneVerification.unverified,
    this.verificationToken,
    this.verificationExpiresAt,
    this.villageId,
    this.villageName = '',
    this.landmark = '',
    this.language,
    this.landOwnership,
    this.farms = const <FarmDraft>[],
    this.currentFarm = 0,
    this.consentData = false,
    this.consentMarketing = false,
    this.updatedAt,
  });

  /// Parses the stored shape.
  factory RegistrationDraft.fromJson(Map<String, Object?> json) =>
      RegistrationDraft(
        farmerId: json['farmer_id']! as String,
        mode: DraftMode.values.byName(
          (json['mode'] as String?) ?? DraftMode.newFarmer.name,
        ),
        step: (json['step'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        verification: PhoneVerification.values.byName(
          (json['verification'] as String?) ??
              PhoneVerification.unverified.name,
        ),
        verificationToken: json['verification_token'] as String?,
        verificationExpiresAt: json['verification_expires_at'] is String
            ? DateTime.tryParse(json['verification_expires_at']! as String)
            : null,
        villageId: json['village_id'] as String?,
        villageName: (json['village_name'] as String?) ?? '',
        landmark: (json['landmark'] as String?) ?? '',
        language: json['language'] as String?,
        landOwnership: json['land_ownership'] as String?,
        farms: <FarmDraft>[
          for (final f in (json['farms'] as List<Object?>?) ?? const [])
            FarmDraft.fromJson(Map<String, Object?>.from(f! as Map)),
        ],
        currentFarm: (json['current_farm'] as num?)?.toInt() ?? 0,
        consentData: json['consent_data'] == true,
        consentMarketing: json['consent_marketing'] == true,
        updatedAt: json['updated_at'] is String
            ? DateTime.tryParse(json['updated_at']! as String)
            : null,
      );

  /// Client-generated uuid of the farmer (existing id in [DraftMode.farm]).
  final String farmerId;

  /// New farmer or farm-only.
  final DraftMode mode;

  /// Zero-based wizard step (A21a = 0 … A21e = 4; A23 uses 0–1).
  final int step;

  /// Farmer name.
  final String name;

  /// 10-digit mobile number without `+91`.
  final String phone;

  /// OTP state.
  final PhoneVerification verification;

  /// Token from `/v1/farmers/phone/verify/confirm`.
  final String? verificationToken;

  /// When [verificationToken] expires (UTC).
  final DateTime? verificationExpiresAt;

  /// Chosen village (synced reference).
  final String? villageId;

  /// Village typed by hand when no villages have synced yet.
  final String villageName;

  /// Landmark near the home.
  final String landmark;

  /// Preferred language code.
  final String? language;

  /// `own` | `leased`.
  final String? landOwnership;

  /// Farms captured so far (at least one).
  final List<FarmDraft> farms;

  /// Index of the farm the boundary / crops steps edit.
  final int currentFarm;

  /// Required data-processing consent.
  final bool consentData;

  /// Optional marketing consent.
  final bool consentMarketing;

  /// Last change (UTC).
  final DateTime? updatedAt;

  /// The farm being edited, if any.
  FarmDraft? get farm =>
      farms.isEmpty ? null : farms[currentFarm.clamp(0, farms.length - 1)];

  /// Every crop plot across every farm.
  List<CropPlotDraft> get allPlots => <CropPlotDraft>[
    for (final f in farms) ...f.plots,
  ];

  /// The phone is verified with a token that is still valid at [now].
  bool isVerifiedAt(DateTime now) =>
      verification == PhoneVerification.verified &&
      verificationToken != null &&
      (verificationExpiresAt == null || now.isBefore(verificationExpiresAt!));

  /// Copy with overrides (`clearVerificationToken` removes the token).
  RegistrationDraft copyWith({
    DraftMode? mode,
    int? step,
    String? name,
    String? phone,
    PhoneVerification? verification,
    String? verificationToken,
    DateTime? verificationExpiresAt,
    bool clearVerificationToken = false,
    String? villageId,
    bool clearVillageId = false,
    String? villageName,
    String? landmark,
    String? language,
    String? landOwnership,
    List<FarmDraft>? farms,
    int? currentFarm,
    bool? consentData,
    bool? consentMarketing,
    DateTime? updatedAt,
  }) => RegistrationDraft(
    farmerId: farmerId,
    mode: mode ?? this.mode,
    step: step ?? this.step,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    verification: verification ?? this.verification,
    verificationToken: clearVerificationToken
        ? null
        : (verificationToken ?? this.verificationToken),
    verificationExpiresAt: clearVerificationToken
        ? null
        : (verificationExpiresAt ?? this.verificationExpiresAt),
    villageId: clearVillageId ? null : (villageId ?? this.villageId),
    villageName: villageName ?? this.villageName,
    landmark: landmark ?? this.landmark,
    language: language ?? this.language,
    landOwnership: landOwnership ?? this.landOwnership,
    farms: farms ?? this.farms,
    currentFarm: currentFarm ?? this.currentFarm,
    consentData: consentData ?? this.consentData,
    consentMarketing: consentMarketing ?? this.consentMarketing,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Stored shape (`kv` key [RegistrationDraft.kvKey]).
  Map<String, Object?> toJson() => <String, Object?>{
    'farmer_id': farmerId,
    'mode': mode.name,
    'step': step,
    'name': name,
    'phone': phone,
    'verification': verification.name,
    'verification_token': verificationToken,
    'verification_expires_at': verificationExpiresAt?.toIso8601String(),
    'village_id': villageId,
    'village_name': villageName,
    'landmark': landmark,
    'language': language,
    'land_ownership': landOwnership,
    'farms': <Object?>[for (final f in farms) f.toJson()],
    'current_farm': currentFarm,
    'consent_data': consentData,
    'consent_marketing': consentMarketing,
    'updated_at': updatedAt?.toIso8601String(),
  };

  /// `kv.key` the draft is stored under.
  static const String kvKey = 'registration.draft';
}
