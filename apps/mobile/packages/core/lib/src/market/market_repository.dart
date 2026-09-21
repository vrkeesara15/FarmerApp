import '../db/app_database.dart';
import '../kisan/kisan_cache.dart';
import '../kisan/kisan_models.dart' show Cached;
import 'market_api.dart';
import 'market_models.dart';

/// FM-012 mandi prices and FM-013 referrals for the farmer app: online
/// first, cached in the encrypted database with the time it was fetched so
/// both screens keep working offline and can always say "as of" (NF-002).
///
/// A mandi price carries **two** dates and the screen shows both: the date
/// the mandi published the figure ([MandiPrices.asOf], part of the payload)
/// and the time we last fetched it ([Cached.asOf]). A stale cache is never
/// silently presented as today's price.
///
/// The referral code arrives from a shared link, never from typing (NF-010
/// forbids typing on farmer screens), so [pendingCode] holds the code a deep
/// link carried until the farmer is signed in and it can be claimed.
class MarketRepository {
  /// Creates the repository.
  MarketRepository({
    required this.db,
    required this.api,
    required DateTime Function() clock,
  }) : cache = KisanCache(db, clock: clock);

  /// The database.
  final AppDatabase db;

  /// REST calls.
  final MarketApi api;

  /// JSON snapshots with "as of" (shared with the M6 / M7 farmer caches).
  final KisanCache cache;

  /// Cache key of the mandi prices.
  static const String pricesKey = 'mandi_prices';

  /// Cache key of the referral profile.
  static const String referralKey = 'referral';

  /// `kv` key of a referral code a deep link carried but that is not claimed
  /// yet (the farmer may not be signed in when the link opens).
  static const String pendingCodeKey = 'kisan.referral_pending_code';

  // --- FM-012 mandi prices ---------------------------------------------------

  /// Fetches the prices for the farmer's crops; false when offline or when
  /// there is no farmer profile yet. The cache is left alone on a failure.
  Future<bool> refreshPrices({int markets = 5}) async {
    final r = await api.mandiPrices(markets: markets);
    if (!r.ok) return false;
    await cache.put(pricesKey, MandiPrices.fromJson(r.body).toJson());
    return true;
  }

  /// The cached prices, live. Null until the first successful fetch.
  Stream<Cached<MandiPrices>?> watchPrices() => cache.watch(pricesKey).map((s) {
    final data = s?.data;
    if (s == null || data is! Map) return null;
    return Cached<MandiPrices>(
      MandiPrices.fromJson(Map<String, Object?>.from(data)),
      s.fetchedAt,
    );
  }).distinct();

  // --- FM-013 referral -------------------------------------------------------

  /// Fetches the farmer's referral code and counts; false when offline.
  Future<bool> refreshReferral() async {
    final r = await api.referral();
    if (!r.ok) return false;
    await cache.put(referralKey, MyReferral.fromJson(r.body).toJson());
    return true;
  }

  /// The cached referral profile, live.
  Stream<Cached<MyReferral>?> watchReferral() =>
      cache.watch(referralKey).map((s) {
        final data = s?.data;
        if (s == null || data is! Map) return null;
        return Cached<MyReferral>(
          MyReferral.fromJson(Map<String, Object?>.from(data)),
          s.fetchedAt,
        );
      }).distinct();

  /// Records an invite about to be shared, so the referral can be matched
  /// when that number registers. Answers false when offline; the share
  /// itself still happens (the code in the message is what attributes it).
  Future<bool> recordInvite({String? phone}) async {
    final r = await api.createInvite(phone: phone);
    if (!r.ok) return false;
    await refreshReferral();
    return true;
  }

  /// Remembers a code an invite link carried, to claim after sign-in.
  Future<void> rememberCode(String? codeOrLink) async {
    final code = referralCodeFrom(codeOrLink);
    if (code == null) return;
    await db.setValue(pendingCodeKey, code);
  }

  /// The code an invite link carried and that is still unclaimed.
  Future<String?> pendingCode() => db.getValue(pendingCodeKey);

  /// Claims [code] (or the remembered one) for the signed-in farmer.
  ///
  /// Answers the problem code when the server refused — `referral_self`,
  /// `referral_already_attributed`, `referral_code_unknown`,
  /// `referral_window_closed`, `referral_disabled` — `'offline'` when the
  /// request never arrived, and null when the referral was attributed.
  /// A refusal clears the pending code: the link is spent either way.
  Future<String?> claim({String? code}) async {
    final value = referralCodeFrom(code) ?? await pendingCode();
    if (value == null) return 'referral_code_unknown';
    final r = await api.claimReferral(value);
    if (r.status == 0) return 'offline';
    await db.removeValue(pendingCodeKey);
    if (!r.ok) return r.code ?? 'referral_code_unknown';
    await refreshReferral();
    return null;
  }
}
