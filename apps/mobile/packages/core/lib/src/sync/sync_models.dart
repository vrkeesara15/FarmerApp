import 'package:flutter/foundation.dart' show immutable, listEquals;

/// Wire names of the entities the client writes through `/v1/sync`
/// (FA-025 contract). Anything else in `changes` lands in `synced_refs`.
abstract final class SyncEntities {
  /// FA-012 farmer.
  static const String farmer = 'farmer';

  /// FA-013 farm.
  static const String farm = 'farm';

  /// FA-013 crop plot.
  static const String cropPlot = 'crop_plot';

  /// FM-002 consent record.
  static const String consentRecord = 'consent_record';

  /// Village reference data (pull only; typed `villages` table).
  static const String village = 'village';

  /// Crop reference data (pull only; kept in `synced_refs`).
  static const String crop = 'crop';

  /// FA-010 duty session (typed `duty_sessions` table).
  static const String dutySession = 'duty_session';

  /// VV-001 location batch (`sync_docs`; points are only ever sent while
  /// on duty).
  static const String locationBatch = 'location_batch';

  /// FA-011 location policy acceptance (`sync_docs`, append-only).
  static const String policyAcceptance = 'policy_acceptance';

  /// FA-014 / FA-017 visit (typed `visits` table).
  static const String visit = 'visit';

  /// FA-015 in-app visit photo (typed `visit_photos` table).
  static const String visitPhoto = 'visit_photo';

  /// FA-016 farmer confirmation (typed `visit_confirmations` table).
  static const String visitConfirmation = 'visit_confirmation';

  /// FA-020 order (typed `orders` + `order_lines` tables; server wins).
  static const String order = 'order';

  /// FA-020 order line (pull only: written inside the `order` create).
  static const String orderLine = 'order_line';

  /// FA-021 payment (typed `payments` table; server wins).
  static const String payment = 'payment';

  /// FA-022 khata entry (pull only; `synced_refs`, append-only).
  static const String khataEntry = 'khata_entry';

  /// ST-007 credit approval request (pull only; `synced_refs`): reaches the
  /// officer who asked, so A56 learns about the decision without polling.
  static const String creditApprovalRequest = 'credit_approval_request';

  /// M6 crop doctor / scouting diagnosis (`sync_docs`; create only, server
  /// wins: the result arrives in the applied echo, by polling and in the
  /// change feed).
  static const String diagnosis = 'diagnosis';

  /// Entities whose create payload must not repeat the id (the server
  /// validates the body strictly and takes the id from `entity_id`).
  static const Set<String> createPayloadWithoutId = <String>{
    payment,
    diagnosis,
  };

  /// Entities with a local table and outbox support.
  static const Set<String> writable = <String>{
    farmer,
    farm,
    cropPlot,
    consentRecord,
    dutySession,
    locationBatch,
    policyAcceptance,
    visit,
    visitPhoto,
    visitConfirmation,
    order,
    payment,
    diagnosis,
  };
}

/// Farmer create payload key carrying the 30-minute OTP proof from
/// `POST /v1/farmers/phone/verify/confirm` (FA-012).
const String phoneVerificationTokenKey = 'phone_verification_token';

/// Client-only companion of [phoneVerificationTokenKey]: ISO-8601 UTC expiry
/// of the token. The engine drops an expired token before sending (the
/// farmer then syncs as unverified instead of being rejected).
const String phoneVerificationExpiresKey = 'phone_verification_expires_at';

/// `order` / `payment` create payload key naming an approved credit request
/// (ST-007 retry; `OrderCreate` / `PaymentCreate`).
const String creditApprovalRequestIdKey = 'credit_approval_request_id';

/// Maximum ops per `/v1/sync` call (contract).
const int maxOpsPerSync = 200;

/// Prefix of a payload placeholder that a completed upload replaces with its
/// `blob_uri`: `upload:<local upload id>`.
const String uploadPlaceholderPrefix = 'upload:';

/// What an outbox op does to its entity.
enum SyncAction {
  /// Insert (base_version 0).
  create,

  /// Partial update.
  update,

  /// Delete.
  delete;

  /// Parses the wire value.
  static SyncAction parse(String value) => SyncAction.values.byName(value);
}

/// Lifecycle of an outbox row.
enum OutboxState {
  /// Waiting to be pushed.
  queued,

  /// In a request right now.
  sending,

  /// Server applied it.
  applied,

  /// Server had already applied it (treated as success).
  duplicate,

  /// Server won; the local row was replaced.
  conflict,

  /// Validation failed; the user must edit and retry.
  rejected;

  /// Parses the stored value.
  static OutboxState parse(String value) => OutboxState.values.byName(value);

  /// Nothing more will happen to this op.
  bool get isTerminal =>
      this == applied || this == duplicate || this == conflict;
}

/// Lifecycle of an upload row.
enum UploadState {
  /// Not started.
  pending,

  /// Some chunks acknowledged.
  uploading,

  /// `blob_uri` available.
  complete,

  /// Gave up (file missing, hash mismatch); the user can retry.
  failed;

  /// Parses the stored value.
  static UploadState parse(String value) => UploadState.values.byName(value);
}

/// A server-side error `{code, detail}` plus any extra problem fields
/// (`outside_geofence` carries `distance_m`, `target`, `radius_m`).
@immutable
class SyncError {
  /// Creates the error.
  const SyncError(
    this.code, [
    this.detail = '',
    this.extra = const <String, Object?>{},
    this.errors = const <Map<String, Object?>>[],
  ]);

  /// Keys of the problem envelope that are not extra data.
  static const Set<String> _envelopeKeys = <String>{
    'code',
    'detail',
    'status',
    'title',
    'type',
    'instance',
    'trace_id',
    'errors',
  };

  /// Parses the wire shape; `null` input gives `null`. Extra fields come
  /// from the top level of the problem and from any `errors[]` entry that
  /// carries them.
  static SyncError? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final extra = <String, Object?>{
      for (final e in json.entries)
        if (!_envelopeKeys.contains(e.key)) e.key: e.value,
    };
    final errors = json['errors'];
    if (errors is List) {
      for (final item in errors) {
        if (item is Map) {
          for (final e in item.entries) {
            if (e.key is String && !_envelopeKeys.contains(e.key)) {
              extra.putIfAbsent(e.key as String, () => e.value);
            }
          }
        }
      }
    }
    final raw = json['extra'];
    if (raw is Map) {
      extra
        ..remove('extra')
        ..addAll(Map<String, Object?>.from(raw));
    }
    return SyncError(
      (json['code'] as String?) ?? 'error',
      (json['detail'] as String?) ?? '',
      extra,
      <Map<String, Object?>>[
        if (errors is List)
          for (final item in errors)
            if (item is Map) Map<String, Object?>.from(item),
      ],
    );
  }

  /// Stable code (e.g. `validation_error`, `duplicate_phone`).
  final String code;

  /// Human-readable detail.
  final String detail;

  /// Extra problem fields (e.g. `distance_m`).
  final Map<String, Object?> extra;

  /// The problem's `errors[]` entries as sent (e.g. one per short line of
  /// an `insufficient_stock` order: `{index, sku_id, requested, available}`).
  final List<Map<String, Object?>> errors;

  static final RegExp _metresInDetail = RegExp(r'(\d+(?:\.\d+)?)\s*m\b');

  /// `approval_request_id` of a `credit_limit_exceeded` rejection (ST-007).
  String? get approvalRequestId => code == 'credit_limit_exceeded'
      ? (extra['approval_request_id'] ??
                errors.firstOrNull?['approval_request_id'])
            as String?
      : null;

  /// `distance_m` of an `outside_geofence` rejection, from the extra fields
  /// or, failing that, the first `<n> m` in the detail text.
  double? get distanceM {
    final v = extra['distance_m'];
    if (v is num) return v.toDouble();
    final m = _metresInDetail.firstMatch(detail);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  /// `target` of an `outside_geofence` rejection (`farm` / `meeting_point`).
  String? get target => extra['target'] as String?;

  /// `radius_m` of an `outside_geofence` rejection.
  double? get radiusM => (extra['radius_m'] as num?)?.toDouble();

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'detail': detail,
    if (extra.isNotEmpty) ...extra,
    if (errors.isNotEmpty) 'errors': errors,
  };

  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';

  @override
  bool operator ==(Object other) =>
      other is SyncError && other.code == code && other.detail == detail;

  @override
  int get hashCode => Object.hash(code, detail);
}

/// One outbox operation on the wire.
@immutable
class SyncOp {
  /// Creates the op.
  const SyncOp({
    required this.opId,
    required this.entity,
    required this.action,
    required this.entityId,
    required this.baseVersion,
    required this.payload,
    required this.clientTs,
  });

  /// Parses the wire shape.
  factory SyncOp.fromJson(Map<String, Object?> json) => SyncOp(
    opId: json['op_id']! as String,
    entity: json['entity']! as String,
    action: SyncAction.parse(json['action']! as String),
    entityId: json['entity_id']! as String,
    baseVersion: (json['base_version'] as num?)?.toInt() ?? 0,
    payload: Map<String, Object?>.from(json['payload']! as Map),
    clientTs: DateTime.parse(json['client_ts']! as String).toUtc(),
  );

  /// Idempotency key.
  final String opId;

  /// Entity wire name.
  final String entity;

  /// Create, update or delete.
  final SyncAction action;

  /// Client-generated uuid of the row.
  final String entityId;

  /// Server version the op is based on (0 for create).
  final int baseVersion;

  /// Fields to write.
  final Map<String, Object?> payload;

  /// When the op was queued (UTC).
  final DateTime clientTs;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'op_id': opId,
    'entity': entity,
    'action': action.name,
    'entity_id': entityId,
    'base_version': baseVersion,
    'payload': payload,
    'client_ts': clientTs.toUtc().toIso8601String(),
  };

  /// Copy with overrides.
  SyncOp copyWith({int? baseVersion, Map<String, Object?>? payload}) => SyncOp(
    opId: opId,
    entity: entity,
    action: action,
    entityId: entityId,
    baseVersion: baseVersion ?? this.baseVersion,
    payload: payload ?? this.payload,
    clientTs: clientTs,
  );
}

/// Per-op outcome from the server.
enum SyncResultStatus {
  /// Applied; `version` is the new row version.
  applied,

  /// Already applied earlier (idempotent replay) — success.
  duplicate,

  /// Server wins; `server` holds the row to keep.
  conflict,

  /// Validation error; keep the op for the user to fix.
  rejected;

  /// Parses the wire value.
  static SyncResultStatus parse(String value) =>
      SyncResultStatus.values.byName(value);
}

/// Result for one op.
@immutable
class SyncOpResult {
  /// Creates the result.
  const SyncOpResult({
    required this.opId,
    required this.status,
    required this.entityId,
    this.version,
    this.error,
    this.server,
  });

  /// Parses the wire shape.
  factory SyncOpResult.fromJson(Map<String, Object?> json) => SyncOpResult(
    opId: json['op_id']! as String,
    status: SyncResultStatus.parse(json['status']! as String),
    entityId: json['entity_id']! as String,
    version: (json['version'] as num?)?.toInt(),
    error: SyncError.fromJson(json['error']),
    server: json['server'] is Map
        ? Map<String, Object?>.from(json['server']! as Map)
        : null,
  );

  /// The op this answers.
  final String opId;

  /// Outcome.
  final SyncResultStatus status;

  /// Row id.
  final String entityId;

  /// New server version (null for deletes and rejections).
  final int? version;

  /// Error on `rejected` (and sometimes `conflict`).
  final SyncError? error;

  /// The server's row on `conflict` (null when it no longer exists).
  final Map<String, Object?>? server;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'op_id': opId,
    'status': status.name,
    'entity_id': entityId,
    'version': version,
    'error': error?.toJson(),
    'server': server,
  };
}

/// One server-side change to pull.
@immutable
class SyncChange {
  /// Creates the change.
  const SyncChange({
    required this.entity,
    required this.action,
    required this.entityId,
    required this.version,
    required this.data,
    required this.seq,
  });

  /// Parses the wire shape.
  factory SyncChange.fromJson(Map<String, Object?> json) => SyncChange(
    entity: json['entity']! as String,
    action: SyncAction.parse(json['action']! as String),
    entityId: json['entity_id']! as String,
    version: (json['version'] as num?)?.toInt() ?? 0,
    data: json['data'] is Map
        ? Map<String, Object?>.from(json['data']! as Map)
        : const <String, Object?>{},
    seq: (json['seq'] as num?)?.toInt() ?? 0,
  );

  /// Entity wire name (may be unknown to this app version).
  final String entity;

  /// Upsert (`create`/`update`) or `delete`.
  final SyncAction action;

  /// Row id.
  final String entityId;

  /// Server version.
  final int version;

  /// Full row.
  final Map<String, Object?> data;

  /// Monotonic change sequence.
  final int seq;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'entity': entity,
    'action': action.name,
    'entity_id': entityId,
    'version': version,
    'data': data,
    'seq': seq,
  };
}

/// `POST /v1/sync` body.
@immutable
class SyncRequest {
  /// Creates the request.
  const SyncRequest({
    required this.deviceId,
    required this.cursor,
    required this.ops,
  });

  /// Device id bound to the session.
  final String deviceId;

  /// Last pull cursor, null on first sync.
  final String? cursor;

  /// Ops in push order (at most [maxOpsPerSync]).
  final List<SyncOp> ops;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'device_id': deviceId,
    'cursor': cursor,
    'ops': ops.map((o) => o.toJson()).toList(growable: false),
  };
}

/// `POST /v1/sync` response.
@immutable
class SyncResponse {
  /// Creates the response.
  const SyncResponse({
    required this.results,
    required this.changes,
    required this.cursor,
    required this.hasMore,
  });

  /// Parses the wire shape.
  factory SyncResponse.fromJson(Map<String, Object?> json) => SyncResponse(
    results: ((json['results'] as List<Object?>?) ?? const <Object?>[])
        .map((r) => SyncOpResult.fromJson(Map<String, Object?>.from(r! as Map)))
        .toList(growable: false),
    changes: ((json['changes'] as List<Object?>?) ?? const <Object?>[])
        .map((c) => SyncChange.fromJson(Map<String, Object?>.from(c! as Map)))
        .toList(growable: false),
    cursor: json['cursor']! as String,
    hasMore: json['has_more'] == true,
  );

  /// One per op sent.
  final List<SyncOpResult> results;

  /// Changes since the request cursor.
  final List<SyncChange> changes;

  /// Cursor to store.
  final String cursor;

  /// More changes are waiting; call again with [cursor].
  final bool hasMore;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'results': results.map((r) => r.toJson()).toList(growable: false),
    'changes': changes.map((c) => c.toJson()).toList(growable: false),
    'cursor': cursor,
    'has_more': hasMore,
  };
}

/// Upload session state (`POST /v1/uploads`, `GET`, chunk `PUT`).
@immutable
class UploadSession {
  /// Creates the session.
  const UploadSession({
    required this.uploadId,
    required this.chunkSize,
    required this.receivedChunks,
    this.expiresAt,
  });

  /// Parses the wire shape; [uploadId] fills in when the body omits it
  /// (chunk `PUT` answers `{received_chunks}` only).
  factory UploadSession.fromJson(
    Map<String, Object?> json, {
    String? uploadId,
    int? chunkSize,
  }) => UploadSession(
    uploadId: (json['upload_id'] as String?) ?? uploadId!,
    chunkSize: (json['chunk_size'] as num?)?.toInt() ?? chunkSize ?? 0,
    receivedChunks: ((json['received_chunks'] as List<Object?>?) ?? const [])
        .map((c) => (c! as num).toInt())
        .toList(growable: false),
    expiresAt: json['expires_at'] is String
        ? DateTime.parse(json['expires_at']! as String).toUtc()
        : null,
  );

  /// Server upload id.
  final String uploadId;

  /// Chunk size the server accepts.
  final int chunkSize;

  /// Acknowledged chunk indexes.
  final List<int> receivedChunks;

  /// When the session expires.
  final DateTime? expiresAt;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'upload_id': uploadId,
    'chunk_size': chunkSize,
    'received_chunks': receivedChunks,
    'expires_at': expiresAt?.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is UploadSession &&
      other.uploadId == uploadId &&
      other.chunkSize == chunkSize &&
      listEquals(other.receivedChunks, receivedChunks) &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode =>
      Object.hash(uploadId, chunkSize, Object.hashAll(receivedChunks));
}

/// `POST /v1/uploads/{id}/complete` response.
@immutable
class UploadResult {
  /// Creates the result.
  const UploadResult({
    required this.blobUri,
    required this.sha256,
    required this.sizeBytes,
    required this.contentType,
  });

  /// Parses the wire shape.
  factory UploadResult.fromJson(Map<String, Object?> json) => UploadResult(
    blobUri: json['blob_uri']! as String,
    sha256: (json['sha256'] as String?) ?? '',
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    contentType: (json['content_type'] as String?) ?? '',
  );

  /// Stable reference the ops carry.
  final String blobUri;

  /// Server-verified hash.
  final String sha256;

  /// Size.
  final int sizeBytes;

  /// MIME type.
  final String contentType;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'blob_uri': blobUri,
    'sha256': sha256,
    'size_bytes': sizeBytes,
    'content_type': contentType,
  };
}

/// The request never completed (offline, timeout, 5xx, auth failure). The
/// engine retries these with backoff; nothing else is retried.
class SyncTransportException implements Exception {
  /// Creates the exception.
  const SyncTransportException(this.message, {this.statusCode, this.code});

  /// What happened.
  final String message;

  /// HTTP status when the server answered.
  final int? statusCode;

  /// Problem `code` when the server answered with problem+json.
  final String? code;

  /// As stored in `sync_states.last_error`.
  SyncError toError() => SyncError(code ?? 'transport', message);

  @override
  String toString() =>
      'SyncTransportException($message'
      '${statusCode == null ? '' : ', $statusCode'})';
}

/// No usable session: the user must sign in again.
class SyncAuthException extends SyncTransportException {
  /// Creates the exception.
  const SyncAuthException([super.message = 'not signed in'])
    : super(statusCode: 401, code: 'unauthenticated');
}
