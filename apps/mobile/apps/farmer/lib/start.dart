import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Where a signed-in farmer lands (FM-001 → FM-002 → FM-003): consent
/// first (the data consent is required to use the app), then the F05
/// welcome once, then home. Fetches the farmer record, profile, orders and
/// the deletion ticket on the way (cached for offline use).
Future<String> routeAfterLogin(WidgetRef ref) async {
  final repo = ref.read(kisanRepositoryProvider);
  await repo.bootstrap();
  ref.invalidate(kisanFarmerIdProvider);
  final consents = await repo.watchConsents().first;
  if (!consents.dataGranted) return AppRoutes.consent;
  if (!await repo.welcomeDone()) return AppRoutes.welcome;
  return AppRoutes.home;
}
