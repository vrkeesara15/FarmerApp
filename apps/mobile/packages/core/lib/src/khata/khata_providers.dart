import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

import '../db/open_database.dart';
import '../sync/sync_providers.dart';
import 'khata_models.dart';
import 'khata_repository.dart';

/// Khata endpoint; the agent app overrides it with [HttpKhataApi].
final Provider<KhataApi> khataApiProvider = Provider<KhataApi>(
  (ref) => FakeKhataApi(),
);

/// Cached khata per farmer.
final Provider<KhataRepository> khataRepositoryProvider =
    Provider<KhataRepository>(
      (ref) => KhataRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(khataApiProvider),
        clock: ref.watch(clockProvider),
      ),
    );

/// A58 khata of a farmer (cached), live.
final StreamProviderFamily<KhataView?, String> khataProvider =
    StreamProvider.family<KhataView?, String>(
      (ref, farmerId) => ref.watch(khataRepositoryProvider).watch(farmerId),
    );
