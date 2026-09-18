import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

import '../db/open_database.dart';
import '../duty/duty_providers.dart' show istDayBounds;
import '../sync/sync_providers.dart';
import 'visit_confirm_api.dart';
import 'visit_flow.dart';
import 'visit_models.dart';
import 'visit_repository.dart';

/// Local visit data over [appDatabaseProvider].
final Provider<VisitRepository> visitRepositoryProvider =
    Provider<VisitRepository>(
      (ref) => VisitRepository(ref.watch(appDatabaseProvider)),
    );

/// FA-016 online calls; the agent app overrides it with
/// [HttpVisitConfirmApi].
final Provider<VisitConfirmApi> visitConfirmApiProvider =
    Provider<VisitConfirmApi>((ref) => FakeVisitConfirmApi());

/// The write path of the visit flow.
final Provider<VisitFlow> visitFlowProvider = Provider<VisitFlow>(
  VisitFlow.new,
);

/// Tenant settings (cached; defaults until pulled).
final FutureProvider<VisitSettings> visitSettingsProvider =
    FutureProvider<VisitSettings>(
      (ref) => ref.watch(visitRepositoryProvider).settings(),
    );

/// A31 / A32 / A33 detail, live.
final StreamProviderFamily<VisitDetail?, String> visitDetailProvider =
    StreamProvider.family<VisitDetail?, String>(
      (ref, id) => ref.watch(visitRepositoryProvider).watchDetail(id),
    );

/// A34 query: a window and an optional status filter.
@immutable
class VisitListQuery {
  /// Creates the query.
  const VisitListQuery({required this.from, required this.to, this.status});

  /// Check-in at or after (UTC).
  final DateTime from;

  /// Check-in before (UTC).
  final DateTime to;

  /// `open` | `verified` | `partial` | `unverified` | null for all.
  final String? status;

  @override
  bool operator ==(Object other) =>
      other is VisitListQuery &&
      other.from == from &&
      other.to == to &&
      other.status == status;

  @override
  int get hashCode => Object.hash(from, to, status);
}

/// A34 rows, live.
final StreamProviderFamily<List<VisitSummary>, VisitListQuery>
visitListProvider = StreamProvider.family<List<VisitSummary>, VisitListQuery>(
  (ref, q) => ref
      .watch(visitRepositoryProvider)
      .watchVisitsBetween(q.from, q.to, status: q.status),
);

/// A22 Visits tab rows, live.
final StreamProviderFamily<List<VisitSummary>, String> farmerVisitsProvider =
    StreamProvider.family<List<VisitSummary>, String>(
      (ref, farmerId) =>
          ref.watch(visitRepositoryProvider).watchVisitsOfFarmer(farmerId),
    );

/// A10 "Visits verified" today (IST), live.
final StreamProvider<int> verifiedVisitsTodayProvider = StreamProvider<int>((
  ref,
) {
  final (from, to) = istDayBounds(ref.watch(clockProvider)());
  return ref.watch(visitRepositoryProvider).watchVerifiedCount(from, to);
});

/// Drives the A31 timer and the live checklist every second; tests
/// override it with an empty stream and advance [clockProvider].
final Provider<Stream<void>> visitTickerProvider = Provider<Stream<void>>(
  (ref) => Stream<void>.periodic(const Duration(seconds: 1)),
);

/// Tick counter screens watch to rebuild with the current clock.
final StreamProvider<int> visitTickProvider = StreamProvider<int>((ref) async* {
  var n = 0;
  yield n;
  await for (final _ in ref.watch(visitTickerProvider)) {
    yield ++n;
  }
});
