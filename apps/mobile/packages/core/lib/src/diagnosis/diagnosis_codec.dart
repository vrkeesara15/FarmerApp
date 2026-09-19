import 'diagnosis_models.dart';

/// How a `diagnosis` row is stored in `sync_docs` (server wins).
///
/// Every write — the applied echo, a poll, a change from the feed — replaces
/// the server fields; this keeps the device-only `_local` block (photo
/// paths, the crop picked on the phone) and, when an earlier answer is
/// replaced (the agronomist confirms or corrects, F27), appends it to
/// `_local.history` and raises `_local.update_unseen` for the banner.
abstract final class DiagnosisCodec {
  /// The data to store for [next] over the stored [previous] row.
  static Map<String, Object?> onWrite(
    Map<String, Object?>? previous,
    Map<String, Object?> next, {
    required DateTime now,
  }) {
    if (previous == null) return next;
    const key = Diagnosis.localKey;
    // A write that carries `_local` owns it (markSeen, markRejected, the
    // engine's merge); a server row (poll, feed) keeps the stored one.
    final local = <String, Object?>{
      ...?((next.containsKey(key) ? next[key] : previous[key]) as Map?)
          ?.cast<String, Object?>(),
    };
    final before = DiagnosisStatus.parse(previous['status']);
    final after = next.containsKey('status')
        ? DiagnosisStatus.parse(next['status'])
        : before;
    final labelChanged =
        next.containsKey('final_problem_id') &&
        previous['final_problem_id'] != next['final_problem_id'];
    if (!before.isWaiting && (before != after || labelChanged)) {
      final problem = (previous['result'] as Map?)?['problem'];
      final names = problem is Map ? problem['names'] : null;
      final history = <Object?>[
        ...((local['history'] as List?) ?? const <Object?>[]),
        DiagnosisHistoryEntry(
          status: before,
          confidence: previous['confidence'] as String?,
          problemNames: names is Map
              ? <String, String>{
                  for (final e in names.entries)
                    if (e.value is String) '${e.key}': e.value! as String,
                }
              : const <String, String>{},
          at:
              _time(previous['reviewed_at']) ??
              _time(previous['answered_at']) ??
              _time(previous['updated_at']) ??
              now,
        ).toJson(),
      ];
      local['history'] = history;
      if (after.isReviewed) local['update_unseen'] = true;
    }
    if (after != DiagnosisStatus.pending) local.remove('failure');
    return <String, Object?>{...next, if (local.isNotEmpty) key: local};
  }

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toUtc() : null;
}
