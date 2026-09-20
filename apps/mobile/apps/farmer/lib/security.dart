import 'dart:io';

import 'package:farmerapp_core/farmerapp_core.dart';

/// SEC-025: what a remote wipe removes from the farmer app: the FA-007
/// push token (so the wiped phone stops receiving this farmer's
/// notifications), the session, the encrypted database and its key (the
/// language survives) and cached files. The farmer app has no duty
/// service and no background sync.
List<WipeStep> kisanWipeSteps({
  required AppDatabase db,
  required DestroyableDatabaseOpener opener,
  required TokenStore tokens,
  required String reason,
  required Future<List<Directory>> Function() directories,
  PushController? push,
}) => <WipeStep>[
  if (push != null) pushTokenWipeStep(push),
  ...standardWipeSteps(
    db: db,
    opener: opener,
    tokens: tokens,
    reason: reason,
    directories: directories,
  ),
];

/// Withdraws this device's push token. It runs before the session is
/// cleared (the call needs it) and never fails the wipe: the server also
/// drops a token FCM reports as unregistered.
WipeStep pushTokenWipeStep(PushController push) =>
    WipeStep('push_token', () async {
      try {
        await push.signedOut();
      } on Object {
        // A wipe must finish even when the phone is offline.
      }
    });
