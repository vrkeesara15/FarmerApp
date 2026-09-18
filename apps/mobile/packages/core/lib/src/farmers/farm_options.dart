import '../i18n/generated/core_localizations.dart';

/// Soil types accepted by `FarmCreate.soil` (API enum `SoilType`).
abstract final class SoilTypes {
  /// Wire values in display order.
  static const List<String> values = <String>[
    'black',
    'red',
    'sandy',
    'loamy',
    'clay',
    'alluvial',
    'laterite',
  ];

  /// Localised label.
  static String label(CoreLocalizations l10n, String value) => switch (value) {
    'black' => l10n.soilBlack,
    'red' => l10n.soilRed,
    'sandy' => l10n.soilSandy,
    'loamy' => l10n.soilLoamy,
    'clay' => l10n.soilClay,
    'alluvial' => l10n.soilAlluvial,
    'laterite' => l10n.soilLaterite,
    _ => value,
  };
}

/// Irrigation types accepted by `FarmCreate.irrigation` (`IrrigationType`).
abstract final class IrrigationTypes {
  /// Wire values in display order.
  static const List<String> values = <String>[
    'rainfed',
    'borewell',
    'canal',
    'tank',
    'open_well',
    'drip',
    'sprinkler',
  ];

  /// Localised label.
  static String label(CoreLocalizations l10n, String value) => switch (value) {
    'rainfed' => l10n.irrigationRainfed,
    'borewell' => l10n.irrigationBorewell,
    'canal' => l10n.irrigationCanal,
    'tank' => l10n.irrigationTank,
    'open_well' => l10n.irrigationOpenWell,
    'drip' => l10n.irrigationDrip,
    'sprinkler' => l10n.irrigationSprinkler,
    _ => value,
  };
}

/// Land ownership (`LandOwnership`).
abstract final class LandOwnershipTypes {
  /// Farmer owns the land.
  static const String own = 'own';

  /// Farmer leases the land.
  static const String leased = 'leased';

  /// Wire values in display order.
  static const List<String> values = <String>[own, leased];

  /// Localised label.
  static String label(CoreLocalizations l10n, String value) => switch (value) {
    own => l10n.ownershipOwn,
    leased => l10n.ownershipLeased,
    _ => value,
  };
}

/// Crop seasons (`Season`), derived from the sowing date.
abstract final class Seasons {
  /// Monsoon season: sown June to September.
  static const String kharif = 'kharif';

  /// Winter season: sown October to February.
  static const String rabi = 'rabi';

  /// Summer season: sown March to May.
  static const String zaid = 'zaid';

  /// Wire values in calendar order.
  static const List<String> values = <String>[kharif, rabi, zaid];

  /// Season a crop sown on [date] belongs to.
  static String forDate(DateTime date) {
    final m = date.month;
    if (m >= 6 && m <= 9) return kharif;
    if (m >= 3 && m <= 5) return zaid;
    return rabi;
  }

  /// Localised label.
  static String label(CoreLocalizations l10n, String value) => switch (value) {
    kharif => l10n.seasonKharif,
    rabi => l10n.seasonRabi,
    zaid => l10n.seasonZaid,
    _ => value,
  };
}

/// A crop from the `crop` reference feed (`synced_refs`), with the pilot
/// list as the offline fallback until the feed has been pulled.
class CropRef {
  /// Creates the reference.
  const CropRef({
    required this.id,
    required this.code,
    required this.name,
    this.names = const <String, String>{},
  });

  /// Parses a `synced_refs` row.
  factory CropRef.fromJson(String id, Map<String, Object?> json) {
    final raw = json['names'];
    return CropRef(
      id: id,
      code: (json['code'] as String?) ?? id,
      name: (json['name'] as String?) ?? (json['code'] as String?) ?? id,
      names: raw is Map
          ? <String, String>{
              for (final e in raw.entries)
                if (e.value is String) e.key as String: e.value! as String,
            }
          : const <String, String>{},
    );
  }

  /// Server id (`crop_plot.crop_id`).
  final String id;

  /// Stable code (`paddy`, `cotton`, ...).
  final String code;

  /// English name.
  final String name;

  /// Names per language code.
  final Map<String, String> names;

  /// Name in [languageCode], falling back to English.
  String nameIn(String languageCode) => names[languageCode] ?? name;

  /// Prefix of the placeholder ids used before the crop feed is pulled.
  static const String pilotIdPrefix = 'pilot:';

  /// SPEC 0.3 pilot crops with placeholder ids (`pilot:<code>`); replaced by
  /// the tenant's `crop` rows once the sync feed delivers them.
  static const List<CropRef> pilotFallback = <CropRef>[
    CropRef(
      id: '${pilotIdPrefix}paddy',
      code: 'paddy',
      name: 'Paddy',
      names: <String, String>{
        'te': 'వరి',
        'hi': 'धान',
        'kn': 'ಭತ್ತ',
        'mr': 'भात',
      },
    ),
    CropRef(
      id: '${pilotIdPrefix}cotton',
      code: 'cotton',
      name: 'Cotton',
      names: <String, String>{
        'te': 'పత్తి',
        'hi': 'कपास',
        'kn': 'ಹತ್ತಿ',
        'mr': 'कापूस',
      },
    ),
    CropRef(
      id: '${pilotIdPrefix}chilli',
      code: 'chilli',
      name: 'Chilli',
      names: <String, String>{
        'te': 'మిరప',
        'hi': 'मिर्च',
        'kn': 'ಮೆಣಸಿನಕಾಯಿ',
        'mr': 'मिरची',
      },
    ),
    CropRef(
      id: '${pilotIdPrefix}maize',
      code: 'maize',
      name: 'Maize',
      names: <String, String>{
        'te': 'మొక్కజొన్న',
        'hi': 'मक्का',
        'kn': 'ಮೆಕ್ಕೆಜೋಳ',
        'mr': 'मका',
      },
    ),
    CropRef(
      id: '${pilotIdPrefix}tomato',
      code: 'tomato',
      name: 'Tomato',
      names: <String, String>{
        'te': 'టమాటా',
        'hi': 'टमाटर',
        'kn': 'ಟೊಮೇಟೊ',
        'mr': 'टोमॅटो',
      },
    ),
    CropRef(
      id: '${pilotIdPrefix}groundnut',
      code: 'groundnut',
      name: 'Groundnut',
      names: <String, String>{
        'te': 'వేరుశనగ',
        'hi': 'मूंगफली',
        'kn': 'ಕಡಲೆಕಾಯಿ',
        'mr': 'भुईमूग',
      },
    ),
  ];
}

/// Indian mobile number as typed (10 digits, 6–9 first).
final RegExp indianMobilePattern = RegExp(r'^[6-9]\d{9}$');

/// `+91` + 10 digits, the shape stored and sent (`FarmerCreate.phone`).
String toE164India(String tenDigits) => '+91$tenDigits';

/// The 10 local digits of an E.164 Indian number (or the input unchanged).
String fromE164India(String phone) =>
    phone.startsWith('+91') ? phone.substring(3) : phone;
