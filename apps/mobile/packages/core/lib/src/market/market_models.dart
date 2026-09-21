/// Models of the M8 farmer APIs: FM-012 mandi prices (a public reference
/// feed, always shown with its date and its source) and FM-013 referrals.
///
/// Contract: docs/prs/M8-market-referral-nlq.md. Money is integer paise per
/// quintal; days are IST `YYYY-MM-DD`.
library;

import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../advisory/advisory_models.dart' show isoDay, parseIsoDate;

int _int(Object? v) => v is num ? v.toInt() : 0;

String _str(Object? v) => v is String ? v : '';

Map<String, String> _names(Object? v) => <String, String>{
  for (final e in (v is Map ? v.entries : const <MapEntry<Object?, Object?>>[]))
    if (e.key is String && e.value is String)
      e.key! as String: e.value! as String,
};

List<Map<String, Object?>> _maps(Object? v) => <Map<String, Object?>>[
  for (final e in (v is List ? v : const <Object?>[]))
    if (e is Map) Map<String, Object?>.from(e),
];

/// One published mandi figure: a market, a date and a price per quintal.
@immutable
class MandiQuote {
  /// Creates a quote.
  const MandiQuote({
    required this.id,
    required this.market,
    required this.district,
    required this.priceDate,
    required this.minPricePaise,
    required this.modalPricePaise,
    required this.maxPricePaise,
    required this.sourceName,
    this.variety = '',
    this.grade = '',
  });

  /// Parses the wire shape.
  factory MandiQuote.fromJson(Map<String, Object?> j) => MandiQuote(
    id: _str(j['id']),
    market: _str(j['market']),
    district: _str(j['district']),
    variety: _str(j['variety']),
    grade: _str(j['grade']),
    priceDate: parseIsoDate(j['price_date']) ?? DateTime.utc(1970),
    minPricePaise: _int(j['min_price_paise']),
    modalPricePaise: _int(j['modal_price_paise']),
    maxPricePaise: _int(j['max_price_paise']),
    sourceName: _str(j['source_name']),
  );

  /// Server id of the reading.
  final String id;

  /// Mandi name as the source publishes it.
  final String market;

  /// District of the mandi.
  final String district;

  /// Variety as published (empty when the source does not break it down).
  final String variety;

  /// Grade as published (empty when the source does not break it down).
  final String grade;

  /// The date the figure was published — the "as of" of this row.
  final DateTime priceDate;

  /// Lowest price per quintal, in paise.
  final int minPricePaise;

  /// The headline (modal) price per quintal, in paise.
  final int modalPricePaise;

  /// Highest price per quintal, in paise.
  final int maxPricePaise;

  /// Display name of the public source, shown next to the date.
  final String sourceName;

  /// The wire shape, for the offline cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'market': market,
    'district': district,
    'variety': variety,
    'grade': grade,
    'price_date': isoDay(priceDate),
    'min_price_paise': minPricePaise,
    'modal_price_paise': modalPricePaise,
    'max_price_paise': maxPricePaise,
    'source_name': sourceName,
  };

  @override
  bool operator ==(Object other) =>
      other is MandiQuote &&
      other.id == id &&
      other.market == market &&
      other.priceDate == priceDate &&
      other.modalPricePaise == modalPricePaise;

  @override
  int get hashCode => Object.hash(id, market, priceDate, modalPricePaise);
}

/// One crop with the prices held for it, nearest market first.
@immutable
class CropPrices {
  /// Creates the group.
  const CropPrices({
    required this.cropId,
    required this.cropCode,
    required this.cropNames,
    required this.quotes,
    this.priceDate,
    this.sourceName,
  });

  /// Parses the wire shape.
  factory CropPrices.fromJson(Map<String, Object?> j) => CropPrices(
    cropId: _str(j['crop_id']),
    cropCode: _str(j['crop_code']),
    cropNames: <String, String>{
      'en': _str(j['crop_name']),
      ..._names(j['crop_names']),
    },
    priceDate: parseIsoDate(j['price_date']),
    sourceName: j['source_name'] is String ? j['source_name']! as String : null,
    quotes: <MandiQuote>[
      for (final q in _maps(j['quotes'])) MandiQuote.fromJson(q),
    ],
  );

  /// Server id of the crop.
  final String cropId;

  /// Crop code, e.g. `paddy`.
  final String cropCode;

  /// Localised crop names (always carries `en`).
  final Map<String, String> cropNames;

  /// The date every quote in [quotes] was published; null when none is held.
  final DateTime? priceDate;

  /// Display name of the source; null when no price is held.
  final String? sourceName;

  /// Quotes of [priceDate], nearest market first.
  final List<MandiQuote> quotes;

  /// True when we hold no price for this crop yet.
  bool get isEmpty => quotes.isEmpty;

  /// The crop's name in [language], falling back to English.
  String name(String language) =>
      cropNames[language] ?? cropNames['en'] ?? cropCode;

  /// The wire shape, for the offline cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'crop_id': cropId,
    'crop_code': cropCode,
    'crop_name': cropNames['en'] ?? cropCode,
    'crop_names': cropNames,
    'price_date': priceDate == null ? null : isoDay(priceDate!),
    'source_name': sourceName,
    'quotes': <Map<String, Object?>>[for (final q in quotes) q.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is CropPrices &&
      other.cropId == cropId &&
      other.priceDate == priceDate &&
      listEquals(other.quotes, quotes);

  @override
  int get hashCode => Object.hash(cropId, priceDate, Object.hashAll(quotes));
}

/// FM-012 `GET /v1/me/mandi-prices`: the farmer's crops with their prices.
@immutable
class MandiPrices {
  /// Creates the payload.
  const MandiPrices({
    required this.crops,
    this.district,
    this.asOf,
    this.indicativeNoteKey = 'mandi.indicative',
  });

  /// Parses the wire shape.
  factory MandiPrices.fromJson(Map<String, Object?> j) => MandiPrices(
    district: j['district'] is String ? j['district']! as String : null,
    asOf: parseIsoDate(j['as_of']),
    indicativeNoteKey: j['indicative_note_key'] is String
        ? j['indicative_note_key']! as String
        : 'mandi.indicative',
    crops: <CropPrices>[
      for (final c in _maps(j['crops'])) CropPrices.fromJson(c),
    ],
  );

  /// The farmer's district (the "nearest markets" ordering is built on it).
  final String? district;

  /// The newest price date across every crop; null when nothing is held.
  final DateTime? asOf;

  /// i18n key of the "prices are indicative" note both apps must show.
  final String indicativeNoteKey;

  /// One group per crop the farmer grows.
  final List<CropPrices> crops;

  /// Crops we actually hold a price for.
  List<CropPrices> get priced => <CropPrices>[
    for (final c in crops)
      if (!c.isEmpty) c,
  ];

  /// The wire shape, for the offline cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'district': district,
    'as_of': asOf == null ? null : isoDay(asOf!),
    'indicative_note_key': indicativeNoteKey,
    'crops': <Map<String, Object?>>[for (final c in crops) c.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is MandiPrices &&
      other.asOf == asOf &&
      listEquals(other.crops, crops);

  @override
  int get hashCode => Object.hash(asOf, Object.hashAll(crops));
}

/// FM-013 `GET /v1/me/referral`: the farmer's own invite code and what it
/// has earned so far.
@immutable
class MyReferral {
  /// Creates the payload.
  const MyReferral({
    required this.code,
    required this.shareLink,
    required this.enabled,
    this.referrerRewardPaise = 0,
    this.storeRewardPaise = 0,
    this.rewardNote,
    this.invited = 0,
    this.attributed = 0,
    this.rewarded = 0,
  });

  /// Parses the wire shape.
  factory MyReferral.fromJson(Map<String, Object?> j) => MyReferral(
    code: _str(j['code']),
    shareLink: _str(j['share_link']),
    enabled: j['enabled'] != false,
    referrerRewardPaise: _int(j['referrer_reward_paise']),
    storeRewardPaise: _int(j['store_reward_paise']),
    rewardNote: j['reward_note'] is String ? j['reward_note']! as String : null,
    invited: _int(j['invited']),
    attributed: _int(j['attributed']),
    rewarded: _int(j['rewarded']),
  );

  /// The farmer's invite code (8 unambiguous characters).
  final String code;

  /// The link the share message carries.
  final String shareLink;

  /// False when the tenant switched referrals off.
  final bool enabled;

  /// What the referrer is promised, in paise (0 until the tenant sets it).
  final int referrerRewardPaise;

  /// What the crediting store is promised, in paise.
  final int storeRewardPaise;

  /// Free text describing the reward, when the tenant set one.
  final String? rewardNote;

  /// Invites shared but not yet registered.
  final int invited;

  /// Farmers who registered with this code.
  final int attributed;

  /// Of those, already rewarded.
  final int rewarded;

  /// The wire shape, for the offline cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'share_link': shareLink,
    'enabled': enabled,
    'referrer_reward_paise': referrerRewardPaise,
    'store_reward_paise': storeRewardPaise,
    'reward_note': rewardNote,
    'invited': invited,
    'attributed': attributed,
    'rewarded': rewarded,
  };

  @override
  bool operator ==(Object other) =>
      other is MyReferral &&
      other.code == code &&
      other.attributed == attributed &&
      other.rewarded == rewarded &&
      other.invited == invited;

  @override
  int get hashCode => Object.hash(code, attributed, rewarded, invited);
}

/// Extracts a referral code from an invite link or a raw code.
///
/// The farmer app never asks anyone to type a code (NF-010): it arrives from
/// the shared link (`https://kisan.farmerapp.in/r/ABCD1234`) or a deep link,
/// so this is the one parser both paths go through. Returns null when the
/// text carries nothing that looks like a code.
String? referralCodeFrom(String? text) {
  if (text == null) return null;
  // Drop a query string or fragment first, so `?utm=x` is never mistaken for
  // the code, then take the last path segment.
  final withoutQuery = text.trim().split(RegExp('[?#]')).first;
  final segments = withoutQuery
      .split(RegExp(r'[/\s]'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (segments.isEmpty) return null;
  final cleaned = segments.last.toUpperCase().replaceAll(
    RegExp('[^A-Z0-9]'),
    '',
  );
  if (cleaned.length < 4 || cleaned.length > 16) return null;
  return cleaned;
}
