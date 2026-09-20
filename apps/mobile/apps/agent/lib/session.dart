import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signs the officer out of this device (A63 "Log out").
///
/// Order matters: the FCM token is withdrawn from the server **while the
/// session still works** (FA-007), then the M7 caches are dropped, then the
/// session itself is cleared. A network failure never blocks the logout —
/// the server also disables a token once FCM rejects it.
Future<void> signOutMitra(WidgetRef ref) async {
  await ref.read(pushControllerProvider).signedOut();
  await ref.read(fieldRepositoryProvider).clearCaches();
  await ref.read(tokenStoreProvider).clear();
}
