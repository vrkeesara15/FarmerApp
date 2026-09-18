import 'package:go_router/go_router.dart';

import 'checkout_screen.dart';
import 'credit_screen.dart';
import 'day_close_screen.dart';
import 'goods_receipt_screen.dart';
import 'invoice_screen.dart';
import 'order_queue_screen.dart';
import 'pos_screen.dart';
import 'stock_screen.dart';
import 'stock_transfer_screen.dart';
import 'store_home_screen.dart';

/// Store-mode paths (SPEC 13.2 S01–S10).
abstract final class StoreRoutes {
  /// S01 Store home.
  static const String home = '/store';

  /// S02 POS.
  static const String pos = '/store/pos';

  /// S03 Checkout.
  static const String checkout = '/store/pos/checkout';

  /// S04 Invoice / receipt share.
  static String invoice(String id) => '/store/invoice/$id';

  /// S05 Order queue.
  static const String queue = '/store/queue';

  /// S06 Stock list.
  static const String stock = '/store/stock';

  /// S07 Goods receipt.
  static const String receipt = '/store/stock/receipt';

  /// S08 Stock transfer.
  static const String transfer = '/store/stock/transfer';

  /// S09 Credit approvals / limits.
  static const String credit = '/store/credit';

  /// S10 Day close.
  static const String dayClose = '/store/day-close';

  /// A63 settings (language, theme, sync, back to the field app).
  static const String settings = '/settings';
}

/// Store-mode routes, mounted by the app router.
List<RouteBase> storeRoutes() => <RouteBase>[
  GoRoute(
    path: StoreRoutes.home,
    builder: (context, state) => const StoreHomeScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: 'pos',
        builder: (context, state) => const PosScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'checkout',
            builder: (context, state) => const CheckoutScreen(),
          ),
        ],
      ),
      GoRoute(
        path: 'invoice/:invoiceId',
        builder: (context, state) =>
            InvoiceScreen(invoiceId: state.pathParameters['invoiceId']!),
      ),
      GoRoute(
        path: 'queue',
        builder: (context, state) => const OrderQueueScreen(),
      ),
      GoRoute(
        path: 'stock',
        builder: (context, state) => const StockScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'receipt',
            builder: (context, state) => const GoodsReceiptScreen(),
          ),
          GoRoute(
            path: 'transfer',
            builder: (context, state) => const StockTransferScreen(),
          ),
        ],
      ),
      GoRoute(
        path: 'credit',
        builder: (context, state) => const CreditScreen(),
      ),
      GoRoute(
        path: 'day-close',
        builder: (context, state) => const DayCloseScreen(),
      ),
    ],
  ),
];
