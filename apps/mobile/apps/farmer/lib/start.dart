import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Where a signed-in farmer lands (FM-001 → FM-002 → FM-003): consent
/// first (the data consent is required to use the app), then the F05
/// welcome once, then home. Fetches the farmer record, profile, orders and
/// the deletion ticket on the way (cached for offline use).
///
/// FM-013: a referral code that an invite link left behind is claimed here,
/// once the farmer record exists — this is how the code is "carried through
/// registration" on the farmer side. It is a best effort: a spent, unknown
/// or self-referring code never blocks the way in.
Future<String> routeAfterLogin(WidgetRef ref) async {
  final repo = ref.read(kisanRepositoryProvider);
  await repo.bootstrap();
  ref.invalidate(kisanFarmerIdProvider);
  await claimPendingReferral(ref);
  final consents = await repo.watchConsents().first;
  if (!consents.dataGranted) return AppRoutes.consent;
  if (!await repo.welcomeDone()) return AppRoutes.welcome;
  return AppRoutes.home;
}

/// FM-013: claims the code an invite link carried, if any.
///
/// Answers the problem code the server gave, `'offline'` when the request
/// never arrived (the code stays for the next attempt), or null when the
/// referral was attributed or there was nothing to claim.
Future<String?> claimPendingReferral(WidgetRef ref) async {
  final market = ref.read(marketRepositoryProvider);
  if (await market.pendingCode() == null) return null;
  return market.claim();
}
