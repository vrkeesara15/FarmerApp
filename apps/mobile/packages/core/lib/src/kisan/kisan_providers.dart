import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

import '../db/open_database.dart';
import '../sync/sync_providers.dart';
import 'kisan_api.dart';
import 'kisan_models.dart';
import 'kisan_repository.dart';

/// The farmer app's REST calls; the app overrides it with [HttpKisanApi].
final Provider<KisanApi> kisanApiProvider = Provider<KisanApi>(
  (ref) => FakeKisanApi(),
);

/// Sends queued writes when online (the farmer app has no background
/// sync: it flushes after a write, on start and on reconnect).
final Provider<Future<void> Function()> kisanFlushProvider =
    Provider<Future<void> Function()>((ref) {
      return () async {
        if (!await ref.read(connectivityMonitorProvider).isOnline()) return;
        await ref.read(syncEngineProvider).syncNow();
      };
    });

/// The farmer app's data.
final Provider<KisanRepository> kisanRepositoryProvider =
    Provider<KisanRepository>((ref) {
      final flush = ref.watch(kisanFlushProvider);
      return KisanRepository(
        db: ref.watch(appDatabaseProvider),
        api: ref.watch(kisanApiProvider),
        outbox: ref.watch(outboxProvider),
        clock: ref.watch(clockProvider),
        ids: ref.watch(idGeneratorProvider),
        onQueued: () => unawaited(flush().catchError((Object _) {})),
      );
    });

/// The farmer id behind the login (null before the first online fetch).
final FutureProvider<String?> kisanFarmerIdProvider = FutureProvider<String?>(
  (ref) => ref.watch(kisanRepositoryProvider).farmerId(),
);

/// Cached profile, live.
final StreamProvider<Cached<FarmerProfile>?> kisanProfileProvider =
    StreamProvider<Cached<FarmerProfile>?>(
      (ref) => ref.watch(kisanRepositoryProvider).watchProfile(),
    );

/// Latest consent per purpose, live.
final StreamProvider<ConsentState> kisanConsentsProvider =
    StreamProvider<ConsentState>(
      (ref) => ref.watch(kisanRepositoryProvider).watchConsents(),
    );

/// F34 orders, live.
final StreamProvider<Cached<List<KisanOrder>>?> kisanOrdersProvider =
    StreamProvider<Cached<List<KisanOrder>>?>(
      (ref) => ref.watch(kisanRepositoryProvider).watchOrders(),
    );

/// F33 one order, live.
final StreamProviderFamily<Cached<KisanOrder>?, String> kisanOrderProvider =
    StreamProvider.family<Cached<KisanOrder>?, String>(
      (ref, id) => ref.watch(kisanRepositoryProvider).watchOrder(id),
    );

/// FM-015 ticket, live.
final StreamProvider<DeletionRequest?> kisanDeletionProvider =
    StreamProvider<DeletionRequest?>(
      (ref) => ref.watch(kisanRepositoryProvider).watchDeletion(),
    );

/// F60 pending prompts, live.
final StreamProvider<List<VisitPrompt>> visitPromptsProvider =
    StreamProvider<List<VisitPrompt>>(
      (ref) => ref.watch(kisanRepositoryProvider).watchPrompts(),
    );
