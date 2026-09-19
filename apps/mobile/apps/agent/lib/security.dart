import 'dart:io';

import 'package:farmerapp_core/farmerapp_core.dart';

/// SEC-025: what a remote wipe removes from the officer app, in order:
/// the duty foreground service and the location sampler, the session, the
/// encrypted database and its key (the language survives), photos and
/// pending uploads and caches, then the background sync jobs.
List<WipeStep> mitraWipeSteps({
  required AppDatabase db,
  required DestroyableDatabaseOpener opener,
  required TokenStore tokens,
  required String reason,
  required ForegroundDutyService dutyService,
  required LocationSampler sampler,
  required Future<List<Directory>> Function() directories,
  required Future<void> Function() cancelBackgroundSync,
}) => <WipeStep>[
  ...standardWipeSteps(
    db: db,
    opener: opener,
    tokens: tokens,
    reason: reason,
    dutyService: dutyService,
    sampler: sampler,
    directories: directories,
  ),
  WipeStep('background_sync', cancelBackgroundSync),
];
