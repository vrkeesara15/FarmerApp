import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/open_database.dart';
import '../kisan/kisan_models.dart' show Cached;
import '../sync/sync_providers.dart';
import 'market_api.dart';
import 'market_models.dart';
import 'market_repository.dart';

/// Shares a text through the OS share sheet — WhatsApp and SMS are the two
/// the farmer picks (FM-013). The farmer app overrides it with `share_plus`.
abstract interface class TextSharer {
  /// Opens the share sheet with [text].
  Future<void> share(String text, {String? subject});
}

/// Records shares instead of opening a sheet (tests, previews).
class FakeTextSharer implements TextSharer {
  /// Everything shared, oldest first.
  final List<String> shared = <String>[];

  @override
  Future<void> share(String text, {String? subject}) async => shared.add(text);
}

/// The OS share sheet; the farmer app overrides it with `share_plus`.
final Provider<TextSharer> textSharerProvider = Provider<TextSharer>(
  (ref) => FakeTextSharer(),
);

/// The M8 REST calls; the app overrides it with [HttpMarketApi].
final Provider<MarketApi> marketApiProvider = Provider<MarketApi>(
  (ref) => FakeMarketApi(),
);

/// FM-012 mandi prices and FM-013 referrals.
final Provider<MarketRepository> marketRepositoryProvider =
    Provider<MarketRepository>(
      (ref) => MarketRepository(
        db: ref.watch(appDatabaseProvider),
        api: ref.watch(marketApiProvider),
        clock: ref.watch(clockProvider),
      ),
    );

/// FM-012 mandi prices for the farmer's crops (cached), live.
final StreamProvider<Cached<MandiPrices>?> mandiPricesProvider =
    StreamProvider<Cached<MandiPrices>?>(
      (ref) => ref.watch(marketRepositoryProvider).watchPrices(),
    );

/// FM-013 the farmer's own referral code and counts (cached), live.
final StreamProvider<Cached<MyReferral>?> myReferralProvider =
    StreamProvider<Cached<MyReferral>?>(
      (ref) => ref.watch(marketRepositoryProvider).watchReferral(),
    );
