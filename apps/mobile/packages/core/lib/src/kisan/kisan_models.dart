import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../geo/geo.dart';

DateTime? _time(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

double? _decimal(Object? v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

int _int(Object? v) => v is num ? v.toInt() : 0;

List<Map<String, Object?>> _maps(Object? v) => <Map<String, Object?>>[
  for (final e in (v is List ? v : const <Object?>[]))
    if (e is Map) Map<String, Object?>.from(e),
];

/// A cached server answer with the time it was fetched ("as of", NF-002).
@immutable
class Cached<T> {
  /// Creates the value.
  const Cached(this.value, this.asOf, {this.stale = false});

  /// The value.
  final T value;

  /// When it was fetched (UTC).
  final DateTime asOf;

  /// The last refresh failed (offline): the screen shows "as of".
  final bool stale;

  @override
  bool operator ==(Object other) =>
      other is Cached<T> &&
      other.value == value &&
      other.asOf == asOf &&
      other.stale == stale;

  @override
  int get hashCode => Object.hash(value, asOf, stale);
}

/// The farmer's field officer (F05 banner, F62 card).
///
/// `GET /v1/farmers/{id}` does not carry the officer's name or phone yet
/// (API follow-up in docs/prs/M6-farmer-app.md): the app reads an optional
/// `officer {id, name, phone}` object and falls back to "your field
/// officer" without it.
@immutable
class OfficerContact {
  /// Creates the contact.
  const OfficerContact({required this.id, this.name, this.phone});

  /// Parses `{id, name, phone}`.
  static OfficerContact? fromJson(Object? json, {String? fallbackId}) {
    if (json is Map) {
      final id = json['id'] ?? fallbackId;
      if (id == null) return null;
      return OfficerContact(
        id: '$id',
        name: json['name'] as String?,
        phone: json['phone'] as String?,
      );
    }
    return fallbackId == null ? null : OfficerContact(id: fallbackId);
  }

  /// User id.
  final String id;

  /// Full name, when the API sends it.
  final String? name;

  /// E.164 phone, when the API sends it.
  final String? phone;

  /// First name for "Your farm details from Ramesh".
  String? get firstName {
    final n = name?.trim();
    if (n == null || n.isEmpty) return null;
    return n.split(RegExp(r'\s+')).first;
  }

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'phone': phone,
  };

  @override
  bool operator ==(Object other) =>
      other is OfficerContact &&
      other.id == id &&
      other.name == name &&
      other.phone == phone;

  @override
  int get hashCode => Object.hash(id, name, phone);
}

/// One crop plot (`CropPlotOut`).
@immutable
class KisanCropPlot {
  /// Creates the plot.
  const KisanCropPlot({
    required this.id,
    required this.farmId,
    required this.cropId,
    required this.version,
    this.stage,
    this.season,
    this.sowingDate,
    this.areaAcres,
  });

  /// Parses `CropPlotOut`.
  factory KisanCropPlot.fromJson(Map<String, Object?> j) => KisanCropPlot(
    id: '${j['id']}',
    farmId: '${j['farm_id']}',
    cropId: '${j['crop_id']}',
    version: _int(j['version']),
    stage: j['stage'] as String?,
    season: j['season'] as String?,
    sowingDate: j['sowing_date'] as String?,
    areaAcres: _decimal(j['area_acres']),
  );

  /// Id.
  final String id;

  /// Farm.
  final String farmId;

  /// Crop reference id.
  final String cropId;

  /// Server row version (PATCH precondition).
  final int version;

  /// `CropStage` wire value.
  final String? stage;

  /// Season.
  final String? season;

  /// ISO date.
  final String? sowingDate;

  /// Area in acres.
  final double? areaAcres;

  @override
  bool operator ==(Object other) =>
      other is KisanCropPlot &&
      other.id == id &&
      other.version == version &&
      other.stage == stage &&
      other.cropId == cropId;

  @override
  int get hashCode => Object.hash(id, version, stage, cropId);
}

/// One farm (`FarmOut`) with its plots.
@immutable
class KisanFarm {
  /// Creates the farm.
  const KisanFarm({
    required this.id,
    required this.version,
    required this.plots,
    this.name,
    this.areaAcres,
    this.soil,
    this.irrigation,
    this.boundary = const <GeoPoint>[],
  });

  /// Parses `FarmOut`.
  factory KisanFarm.fromJson(Map<String, Object?> j) => KisanFarm(
    id: '${j['id']}',
    version: _int(j['version']),
    name: j['name'] as String?,
    areaAcres: _decimal(j['area_acres']),
    soil: j['soil'] as String?,
    irrigation: j['irrigation'] as String?,
    boundary: polygonFromGeoJson(j['boundary']),
    plots: <KisanCropPlot>[
      for (final p in _maps(j['crop_plots']))
        if (p['deleted_at'] == null) KisanCropPlot.fromJson(p),
    ],
  );

  /// Id.
  final String id;

  /// Server row version.
  final int version;

  /// Label.
  final String? name;

  /// Declared area.
  final double? areaAcres;

  /// `SoilType`.
  final String? soil;

  /// `IrrigationType`.
  final String? irrigation;

  /// Boundary ring (empty when not mapped).
  final List<GeoPoint> boundary;

  /// Crop plots.
  final List<KisanCropPlot> plots;

  @override
  bool operator ==(Object other) =>
      other is KisanFarm &&
      other.id == id &&
      other.version == version &&
      other.soil == soil &&
      other.irrigation == irrigation &&
      listEquals(other.plots, plots);

  @override
  int get hashCode =>
      Object.hash(id, version, soil, irrigation, Object.hashAll(plots));
}

/// Consent purposes (`ConsentPurpose`).
abstract final class ConsentPurposes {
  /// "Use my data to give crop advice" (required).
  static const String data = 'data';

  /// "Send me offers and tips" (optional, withdrawable).
  static const String marketing = 'marketing';
}

/// One consent row (`ConsentRecordOut`, or a local one still queued).
@immutable
class ConsentEntry {
  /// Creates the entry.
  const ConsentEntry({
    required this.id,
    required this.purpose,
    required this.granted,
    required this.at,
    this.version,
    this.channel,
    this.pending = false,
  });

  /// Parses `ConsentRecordOut` (a withdrawal has `withdrawn_at`).
  factory ConsentEntry.fromJson(Map<String, Object?> j) {
    final withdrawn = _time(j['withdrawn_at']);
    final granted = _time(j['granted_at']);
    return ConsentEntry(
      id: '${j['id']}',
      purpose: (j['purpose'] as String?) ?? '',
      granted: withdrawn == null && granted != null,
      at: withdrawn ?? granted ?? _time(j['created_at']) ?? DateTime.utc(1970),
      version: j['version'] as String?,
      channel: j['channel'] as String?,
    );
  }

  /// Row id.
  final String id;

  /// `data` | `marketing`.
  final String purpose;

  /// Granted (else withdrawn / refused).
  final bool granted;

  /// When (UTC).
  final DateTime at;

  /// Consent text version.
  final String? version;

  /// `app` | `officer`.
  final String? channel;

  /// Still in the outbox (recorded offline).
  final bool pending;

  @override
  bool operator ==(Object other) =>
      other is ConsentEntry &&
      other.id == id &&
      other.granted == granted &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(id, granted, pending);
}

/// The latest decision per purpose (F04, F70 consent settings).
@immutable
class ConsentState {
  /// Creates the state.
  const ConsentState({this.data, this.marketing});

  /// Folds [entries] (any order): the newest row per purpose wins.
  factory ConsentState.of(Iterable<ConsentEntry> entries) {
    ConsentEntry? newest(String purpose) {
      ConsentEntry? best;
      for (final e in entries) {
        if (e.purpose != purpose) continue;
        if (best == null || !e.at.isBefore(best.at)) best = e;
      }
      return best;
    }

    return ConsentState(
      data: newest(ConsentPurposes.data),
      marketing: newest(ConsentPurposes.marketing),
    );
  }

  /// Latest data consent row.
  final ConsentEntry? data;

  /// Latest marketing consent row.
  final ConsentEntry? marketing;

  /// Data consent given (required to use the app).
  bool get dataGranted => data?.granted ?? false;

  /// Offers and tips allowed.
  bool get marketingGranted => marketing?.granted ?? false;

  /// A decision is still waiting to be sent.
  bool get pending => (data?.pending ?? false) || (marketing?.pending ?? false);

  @override
  bool operator ==(Object other) =>
      other is ConsentState &&
      other.data == data &&
      other.marketing == marketing;

  @override
  int get hashCode => Object.hash(data, marketing);
}

/// The signed-in farmer (`FarmerDetailOut`).
@immutable
class FarmerProfile {
  /// Creates the profile.
  const FarmerProfile({
    required this.id,
    required this.name,
    required this.version,
    required this.farms,
    required this.consents,
    this.phone,
    this.villageId,
    this.language,
    this.source,
    this.registeredBy,
    this.officer,
  });

  /// Parses `FarmerDetailOut` (plus the optional `officer` object).
  factory FarmerProfile.fromJson(Map<String, Object?> j) => FarmerProfile(
    id: '${j['id']}',
    name: (j['name'] as String?) ?? '',
    version: _int(j['version']),
    phone: j['phone'] as String?,
    villageId: j['village_id'] as String?,
    language: j['language'] as String?,
    source: j['source'] as String?,
    registeredBy: j['registered_by'] as String?,
    officer: OfficerContact.fromJson(
      j['officer'],
      fallbackId: j['registered_by'] as String?,
    ),
    farms: <KisanFarm>[
      for (final f in _maps(j['farms']))
        if (f['deleted_at'] == null) KisanFarm.fromJson(f),
    ],
    consents: <ConsentEntry>[
      for (final c in _maps(j['consents'])) ConsentEntry.fromJson(c),
    ],
  );

  /// Farmer id.
  final String id;

  /// Name.
  final String name;

  /// Server row version.
  final int version;

  /// E.164 phone.
  final String? phone;

  /// Village.
  final String? villageId;

  /// Preferred language.
  final String? language;

  /// How the farmer was acquired (`field_officer`, `store`, ...).
  final String? source;

  /// The officer who registered the farmer.
  final String? registeredBy;

  /// The officer's contact (see [OfficerContact]).
  final OfficerContact? officer;

  /// Farms with plots.
  final List<KisanFarm> farms;

  /// Consent history.
  final List<ConsentEntry> consents;

  /// FM-003: an officer registered this farmer (F05 confirm, not setup).
  bool get registeredByOfficer =>
      registeredBy != null || source == 'field_officer';

  /// First name for the greeting.
  String get firstName {
    final n = name.trim();
    return n.isEmpty ? n : n.split(RegExp(r'\s+')).first;
  }

  /// Every plot of every farm.
  List<KisanCropPlot> get plots => <KisanCropPlot>[
    for (final f in farms) ...f.plots,
  ];

  @override
  bool operator ==(Object other) =>
      other is FarmerProfile &&
      other.id == id &&
      other.version == version &&
      other.name == name &&
      other.villageId == villageId &&
      other.officer == officer &&
      listEquals(other.farms, farms) &&
      listEquals(other.consents, consents);

  @override
  int get hashCode => Object.hash(
    id,
    version,
    name,
    villageId,
    officer,
    Object.hashAll(farms),
    Object.hashAll(consents),
  );
}

/// One order line (`OrderLineOut`, names from the device's catalogue).
@immutable
class KisanOrderLine {
  /// Creates the line.
  const KisanOrderLine({
    required this.skuId,
    required this.qty,
    required this.lineTotalPaise,
    this.name,
    this.pack,
  });

  /// Parses `OrderLineOut` (+ optional `product_name` / `pack_label`).
  factory KisanOrderLine.fromJson(Map<String, Object?> j) => KisanOrderLine(
    skuId: '${j['sku_id']}',
    qty: _decimal(j['qty']) ?? 0,
    lineTotalPaise: _int(j['line_total_paise']),
    name: j['product_name'] as String?,
    pack: j['pack_label'] as String?,
  );

  /// SKU.
  final String skuId;

  /// Quantity.
  final double qty;

  /// Line total (paise).
  final int lineTotalPaise;

  /// Product name when known.
  final String? name;

  /// Pack label when known.
  final String? pack;
}

/// A farmer's order (`OrderOut` / `OrderDetailOut`).
@immutable
class KisanOrder {
  /// Creates the order.
  const KisanOrder({
    required this.id,
    required this.status,
    required this.fulfilment,
    required this.totalPaise,
    this.placedAt,
    this.storeId,
    this.lines = const <KisanOrderLine>[],
    this.events = const <(String, DateTime?)>[],
    this.paidPaise = 0,
    this.paymentModes = const <String>[],
    this.invoiceNo,
  });

  /// Parses `OrderOut` / `OrderDetailOut`.
  factory KisanOrder.fromJson(Map<String, Object?> j) {
    final payments = _maps(j['payments']);
    return KisanOrder(
      id: '${j['id']}',
      status: (j['status'] as String?) ?? 'placed',
      fulfilment: (j['fulfilment'] as String?) ?? 'pickup',
      totalPaise: _int(j['total_paise']),
      placedAt: _time(j['placed_at']) ?? _time(j['created_at']),
      storeId: j['store_id'] as String?,
      invoiceNo: j['invoice_no'] as String?,
      lines: <KisanOrderLine>[
        for (final l in _maps(j['lines'])) KisanOrderLine.fromJson(l),
      ],
      events: <(String, DateTime?)>[
        for (final e in _maps(j['events']))
          if (e['to_status'] is String)
            (e['to_status']! as String, _time(e['created_at'])),
      ],
      paidPaise: payments
          .where((p) => p['status'] == 'paid' || p['status'] == 'reconciled')
          .fold(0, (a, p) => a + _int(p['amount_paise'])),
      paymentModes: <String>[
        for (final p in payments)
          if (p['mode'] is String) p['mode']! as String,
      ],
    );
  }

  /// Id.
  final String id;

  /// ST-005 status.
  final String status;

  /// `pickup` | `delivery`.
  final String fulfilment;

  /// Server total (paise).
  final int totalPaise;

  /// Placed at (UTC).
  final DateTime? placedAt;

  /// Store.
  final String? storeId;

  /// Lines (detail only).
  final List<KisanOrderLine> lines;

  /// Status history, oldest first.
  final List<(String, DateTime?)> events;

  /// Paid so far.
  final int paidPaise;

  /// Modes of the order's payments.
  final List<String> paymentModes;

  /// GST invoice number once issued.
  final String? invoiceNo;

  /// Fully paid.
  bool get paid => totalPaise > 0 && paidPaise >= totalPaise;

  /// On the khata (credit).
  bool get onCredit => paymentModes.contains('credit');

  /// F33 step: 0 placed, 1 packed, 2 ready, 3 collected; -1 cancelled.
  int get step => switch (status) {
    'cancelled' => -1,
    'packed' => 1,
    'ready' => 2,
    'handed_over' || 'delivered' => 3,
    _ => 0,
  };

  /// When the order reached F33 [step] (from the history), if known.
  DateTime? reachedAt(int step) {
    for (final (status, at) in events) {
      final s = switch (status) {
        'packed' => 1,
        'ready' => 2,
        'handed_over' || 'delivered' => 3,
        'placed' => 0,
        _ => -2,
      };
      if (s == step) return at;
    }
    return step == 0 ? placedAt : null;
  }
}

/// `GET/POST /v1/me/deletion-request` (FM-015):
/// `{ticket_id, status, due_by}`.
@immutable
class DeletionRequest {
  /// Creates the request.
  const DeletionRequest({
    required this.ticketId,
    required this.status,
    this.dueBy,
  });

  /// Parses the API shape.
  factory DeletionRequest.fromJson(Map<String, Object?> j) => DeletionRequest(
    ticketId: '${j['ticket_id']}',
    status: (j['status'] as String?) ?? 'received',
    dueBy: _time(j['due_by']),
  );

  /// Ticket id (a uuid from `POST /v1/me/deletion-request`).
  final String ticketId;

  /// The reference the farmer reads out on the phone: the first 8
  /// characters of a uuid ticket, upper case (the full id stays stored).
  String get shortTicket {
    final uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}$');
    return uuid.hasMatch(ticketId)
        ? ticketId.substring(0, 8).toUpperCase()
        : ticketId;
  }

  /// `received`, `in_progress`, `completed` or `rejected`.
  final String status;

  /// When the deletion must be done by (UTC).
  final DateTime? dueBy;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'ticket_id': ticketId,
    'status': status,
    'due_by': dueBy?.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is DeletionRequest &&
      other.ticketId == ticketId &&
      other.status == status &&
      other.dueBy == dueBy;

  @override
  int get hashCode => Object.hash(ticketId, status, dueBy);
}

/// Claims of a visit confirmation token (push payload or QR) the app
/// reads without verifying (the server verifies): `vid`, `cid`, `ch`,
/// `exp`.
@immutable
class ConfirmToken {
  /// Creates the claims.
  const ConfirmToken({
    required this.raw,
    required this.visitId,
    this.confirmationId,
    this.channel,
    this.expiresAt,
  });

  /// Decodes a JWT payload; null when [raw] is not a confirmation token.
  static ConfirmToken? decode(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map || payload['vid'] is! String) return null;
      if (payload['typ'] != null && payload['typ'] != 'visit_confirm') {
        return null;
      }
      final exp = payload['exp'];
      return ConfirmToken(
        raw: raw.trim(),
        visitId: payload['vid']! as String,
        confirmationId: payload['cid'] as String?,
        channel: payload['ch'] as String?,
        expiresAt: exp is num
            ? DateTime.fromMillisecondsSinceEpoch(
                exp.toInt() * 1000,
                isUtc: true,
              )
            : null,
      );
    } on FormatException {
      return null;
    }
  }

  /// The token as scanned / received.
  final String raw;

  /// Visit.
  final String visitId;

  /// Confirmation row.
  final String? confirmationId;

  /// `app_push` | `qr`.
  final String? channel;

  /// Expiry.
  final DateTime? expiresAt;
}

/// A pending "Did `officer` visit your farm today?" prompt (F60).
@immutable
class VisitPrompt {
  /// Creates the prompt.
  const VisitPrompt({
    required this.visitId,
    this.token,
    this.officerName,
    this.expiresAt,
    this.channel = 'app_push',
  });

  /// Parses the stored / push shape.
  factory VisitPrompt.fromJson(Map<String, Object?> j) => VisitPrompt(
    visitId: '${j['visit_id']}',
    token: j['token'] as String?,
    officerName: j['officer_name'] as String?,
    expiresAt: _time(j['expires_at']),
    channel: (j['channel'] as String?) ?? 'app_push',
  );

  /// Visit.
  final String visitId;

  /// Signed token (push payload); null when only the sync feed told us.
  final String? token;

  /// Officer's name.
  final String? officerName;

  /// Expiry.
  final DateTime? expiresAt;

  /// Channel the token is for.
  final String channel;

  /// First name.
  String? get officerFirstName {
    final n = officerName?.trim();
    if (n == null || n.isEmpty) return null;
    return n.split(RegExp(r'\s+')).first;
  }

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'visit_id': visitId,
    'token': token,
    'officer_name': officerName,
    'expires_at': expiresAt?.toIso8601String(),
    'channel': channel,
  };

  @override
  bool operator ==(Object other) =>
      other is VisitPrompt &&
      other.visitId == visitId &&
      other.token == token &&
      other.officerName == officerName &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(visitId, token, officerName, expiresAt);
}

/// Outcome of a write the farmer app makes online first.
enum KisanWrite {
  /// The server has it.
  done,

  /// Offline: queued in the outbox, sent on the next sync.
  queued,

  /// Offline and the write cannot be queued: try again online.
  offline,

  /// The server refused.
  refused,
}
