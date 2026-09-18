import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

import '../db/open_database.dart';
import '../sync/sync_providers.dart';
import 'order_models.dart';
import 'order_repository.dart';

/// Shares a text (the invoice link) through the OS share sheet; the agent
/// app overrides it with `share_plus` (WhatsApp is picked there).
abstract interface class InvoiceSharer {
  /// Opens the share sheet with [text].
  Future<void> share(String text, {String? subject});
}

/// Records shares (tests, previews).
class FakeInvoiceSharer implements InvoiceSharer {
  /// Texts shared, in order.
  final List<String> shared = <String>[];

  @override
  Future<void> share(String text, {String? subject}) async => shared.add(text);
}

/// The OS share sheet.
final Provider<InvoiceSharer> invoiceSharerProvider = Provider<InvoiceSharer>(
  (ref) => FakeInvoiceSharer(),
);

/// Local orders + the `order` op.
final Provider<OrderRepository> orderRepositoryProvider =
    Provider<OrderRepository>(
      (ref) => OrderRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(outboxProvider),
        ids: ref.watch(idGeneratorProvider),
      ),
    );

/// A57 order, live.
final StreamProviderFamily<OrderView?, String> orderViewProvider =
    StreamProvider.family<OrderView?, String>(
      (ref, id) => ref.watch(orderRepositoryProvider).watchOrder(id),
    );

/// A22 Orders tab, live.
final StreamProviderFamily<List<OrderView>, String> farmerOrdersProvider =
    StreamProvider.family<List<OrderView>, String>(
      (ref, farmerId) =>
          ref.watch(orderRepositoryProvider).watchFarmerOrders(farmerId),
    );

/// Orders nav tab, live.
final StreamProvider<List<OrderView>> recentOrdersProvider =
    StreamProvider<List<OrderView>>(
      (ref) => ref.watch(orderRepositoryProvider).watchRecent(),
    );
