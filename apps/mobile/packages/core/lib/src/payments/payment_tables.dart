import 'package:drift/drift.dart';

import '../db/app_database.dart' show SyncedRow;

/// FA-021 payment collected (or requested) by the officer (sync entity
/// `payment`). Cash and credit are captured offline through the outbox;
/// UPI QR and payment links are created online and stored here for A59.
/// `status` and `amount_paise` are server-owned once the server has seen
/// the payment.
@DataClassName('PaymentRow')
@TableIndex(name: 'payments_collected', columns: <Symbol>{#collectedAt})
class Payments extends Table with SyncedRow {
  /// Order paid for (null for khata dues).
  TextColumn get orderId => text().nullable()();

  /// Farmer.
  TextColumn get farmerId => text().nullable()();

  /// Store.
  TextColumn get storeId => text().nullable()();

  /// `upi_qr` | `payment_link` | `cash` | `card_terminal` | `credit`.
  TextColumn get mode => text()();

  /// Amount (paise): the device's expectation until the server answers.
  IntColumn get amountPaise => integer().withDefault(const Constant(0))();

  /// `queued` (device only) | `created` | `pending` |
  /// `pending_reconciliation` | `paid` | `failed` | `refunded` |
  /// `reconciled`.
  TextColumn get status => text().withDefault(const Constant('queued'))();

  /// Cash receipt blob URI (or `upload:<id>` while queued).
  TextColumn get receiptUri => text().nullable()();

  /// Local file of the receipt photo.
  TextColumn get receiptPath => text().nullable()();

  /// Collecting user (server).
  TextColumn get collectedBy => text().nullable()();

  /// When the officer collected / requested it (UTC).
  DateTimeColumn get collectedAt => dateTime()();

  /// When the server marked it paid (UTC).
  DateTimeColumn get paidAt => dateTime().nullable()();

  /// UPI QR / link expiry (UTC).
  DateTimeColumn get expiresAt => dateTime().nullable()();

  /// Payment link URL.
  TextColumn get shortUrl => text().nullable()();

  /// `sms` | `whatsapp` (payment link).
  TextColumn get sentVia => text().nullable()();

  /// UPI QR payload (A53, while waiting).
  TextColumn get qrPayload => text().nullable()();

  /// Provider failure reason.
  TextColumn get failureReason => text().nullable()();

  /// JSON of server fields this app does not model.
  TextColumn get extra => text().withDefault(const Constant('{}'))();
}
