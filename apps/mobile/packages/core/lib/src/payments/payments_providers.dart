import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

import '../db/app_database.dart';
import '../db/open_database.dart';
import '../duty/duty_providers.dart' show istDayBounds;
import '../farmers/farmers_providers.dart';
import '../photo/photo_processor.dart';
import '../photo/photo_quality.dart';
import '../state/auth_flow.dart' show tokenStoreProvider;
import '../sync/sync_providers.dart';
import 'payment_models.dart';
import 'payment_repository.dart';
import 'payments_api.dart';

/// Online payment calls; the agent app overrides it with [HttpPaymentsApi].
final Provider<PaymentsApi> paymentsApiProvider = Provider<PaymentsApi>(
  (ref) => FakePaymentsApi(),
);

/// A53 poll wait; tests override it with a fake-clock advance.
final Provider<Future<void> Function(Duration)> upiSleepProvider =
    Provider<Future<void> Function(Duration)>((ref) => Future<void>.delayed);

/// Payments on the device.
final Provider<PaymentRepository> paymentRepositoryProvider =
    Provider<PaymentRepository>(
      (ref) => PaymentRepository(
        db: ref.watch(appDatabaseProvider),
        outbox: ref.watch(outboxProvider),
        api: ref.watch(paymentsApiProvider),
        photos: ref.watch(photoStoreProvider),
        ids: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
      ),
    );

/// A payment with its outbox state, live.
final StreamProviderFamily<PaymentView?, String> paymentViewProvider =
    StreamProvider.family<PaymentView?, String>(
      (ref, id) => ref.watch(paymentRepositoryProvider).watchPayment(id),
    );

/// Payments of an order, live (A57).
final StreamProviderFamily<List<PaymentView>, String> orderPaymentsProvider =
    StreamProvider.family<List<PaymentView>, String>(
      (ref, orderId) =>
          ref.watch(paymentRepositoryProvider).watchOrderPayments(orderId),
    );

/// The signed-in user's id (A59 "collected by me"); null in previews.
final FutureProvider<String?> currentUserIdProvider = FutureProvider<String?>(
  (ref) async => (await ref.watch(tokenStoreProvider).read())?.user.id,
);

/// A59 window.
enum CollectionsRange {
  /// Today (IST).
  today,

  /// The 7 IST days ending today.
  week,
}

/// A59 payments and totals, live.
final StreamProviderFamily<CollectionsSummary, CollectionsRange>
collectionsProvider =
    StreamProvider.family<CollectionsSummary, CollectionsRange>((ref, range) {
      final (from, to) = istDayBounds(ref.watch(clockProvider)());
      final start = range == CollectionsRange.today
          ? from
          : from.subtract(const Duration(days: 6));
      final me = ref.watch(currentUserIdProvider).value;
      return ref
          .watch(paymentRepositoryProvider)
          .watchCollections(start, to, collectedBy: me);
    });

/// A processed receipt photo waiting for "Use photo".
@immutable
class PendingReceipt {
  /// Creates the receipt.
  const PendingReceipt({required this.processed, required this.quality});

  /// NF-004 output.
  final ProcessedPhoto processed;

  /// Blur / darkness check.
  final PhotoQualityResult quality;

  /// JPEG bytes.
  Uint8List get bytes => processed.bytes;
}

/// A55: opens the in-app camera (no gallery path) and runs the NF-004
/// pipeline and quality gate on the receipt. Null when cancelled.
final Provider<Future<PendingReceipt?> Function()> receiptCaptureProvider =
    Provider<Future<PendingReceipt?> Function()>((ref) {
      return () async {
        final bytes = await ref.read(cameraSourceProvider).capture();
        if (bytes == null) return null;
        final processed = await PhotoProcessor.process(
          bytes,
          captureTime: ref.read(clockProvider)(),
        );
        final quality = await PhotoQualityCheck.evaluate(processed.bytes);
        return PendingReceipt(processed: processed, quality: quality);
      };
    });

/// A53 / A54 countdown ticks every second; tests override it with an empty
/// stream and move [clockProvider].
final Provider<Stream<void>> paymentTickerProvider = Provider<Stream<void>>(
  (ref) => Stream<void>.periodic(const Duration(seconds: 1)),
);

/// Tick counter the payment screens watch to redraw the countdown.
final StreamProvider<int> paymentTickProvider = StreamProvider<int>((
  ref,
) async* {
  var n = 0;
  yield n;
  await for (final _ in ref.watch(paymentTickerProvider)) {
    yield ++n;
  }
});

/// The target of an existing payment (to create another one for it).
PaymentTarget targetOf(PaymentRow p) => p.orderId != null
    ? PaymentTarget.order(
        orderId: p.orderId!,
        farmerId: p.farmerId,
        storeId: p.storeId,
      )
    : PaymentTarget.dues(
        farmerId: p.farmerId ?? '',
        storeId: p.storeId ?? '',
        duesAmountPaise: p.amountPaise,
      );
