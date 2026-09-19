import 'dart:io';

import 'package:farmerapp_core/farmerapp_core.dart';

/// SEC-025: what a remote wipe removes from the farmer app: the session,
/// the encrypted database and its key (the language survives) and cached
/// files. The farmer app has no duty service and no background sync.
List<WipeStep> kisanWipeSteps({
  required AppDatabase db,
  required DestroyableDatabaseOpener opener,
  required TokenStore tokens,
  required String reason,
  required Future<List<Directory>> Function() directories,
}) => standardWipeSteps(
  db: db,
  opener: opener,
  tokens: tokens,
  reason: reason,
  directories: directories,
);
