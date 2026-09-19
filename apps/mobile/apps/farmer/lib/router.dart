import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/consent_screen.dart';
import 'screens/consent_settings_screen.dart';
import 'screens/crop_doctor_placeholder_screen.dart';
import 'screens/delete_account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/khata_screen.dart';
import 'screens/language_screen.dart';
import 'screens/my_crops_screen.dart';
import 'screens/officer_screen.dart';
import 'screens/orders/cart_screen.dart';
import 'screens/orders/my_orders_screen.dart';
import 'screens/orders/order_tracking_screen.dart';
import 'screens/orders/pay_screen.dart';
import 'screens/orders/product_detail_screen.dart';
import 'screens/orders/shop_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/payment_receipt_screen.dart';
import 'screens/phone_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/visit/visit_confirm_screen.dart';
import 'screens/visit/visit_rating_screen.dart';
import 'screens/visit/visit_scan_screen.dart';
import 'screens/welcome_screen.dart';

/// Route paths of the farmer app (SPEC 13.3).
abstract final class AppRoutes {
  /// F01 Language picker with audio.
  static const String language = '/';

  /// F02 Phone login.
  static const String phone = '/login';

  /// F03 OTP.
  static const String otp = '/login/otp';

  /// F04 Consent.
  static const String consent = '/consent';

  /// F05 Welcome (officer-registered confirm, or quick setup).
  static const String welcome = '/welcome';

  /// F10 Home.
  static const String home = '/home';

  /// F20 Crop doctor (placeholder until the crop doctor task).
  static const String cropDoctor = '/crop-doctor';

  /// F30 catalogue by category (entry to product detail).
  static const String shop = '/shop';

  /// F30 Product detail: `/shop/<skuId>`.
  static String product(String skuId) => '/shop/$skuId';

  /// F31 Cart and pickup / delivery.
  static const String cart = '/cart';

  /// F32 Pay.
  static const String pay = '/cart/pay';

  /// F34 My orders.
  static const String orders = '/orders';

  /// F33 Order tracking: `/orders/<id>`.
  static String order(String id) => '/orders/$id';

  /// F40 My crops and farms.
  static const String crops = '/crops';

  /// F50 Khata.
  static const String khata = '/khata';

  /// F51 Payment success receipt.
  static const String receipt = '/khata/receipt';

  /// F60 Visit confirmation prompt: `/visit/<visitId>`.
  static String visit(String visitId) => '/visit/$visitId';

  /// F60 QR scan.
  static const String visitScan = '/visit-scan';

  /// F61 Rating: `/visit/<visitId>/rate` (token in `extra`).
  static String visitRate(String visitId) => '/visit/$visitId/rate';

  /// F62 My field officer.
  static const String officer = '/officer';

  /// F70 Me.
  static const String me = '/me';

  /// Legacy name of [me].
  static const String settings = me;

  /// F70 consent settings.
  static const String consentSettings = '/me/consent';

  /// F70 Delete my account.
  static const String deleteAccount = '/me/delete';

  /// Signed out by your administrator (SEC-025; the officer app's A08).
  static const String signedOut = '/signed-out';

  /// Routes where typing is allowed (NF-010: phone number and OTP only).
  static const Set<String> typingAllowed = <String>{phone, otp};
}

/// Opens on the home screen when a session is stored (set in `main`).
final Provider<bool> signedInProvider = Provider<bool>((ref) => false);

/// The app router; after a remote wipe it opens on the signed-out screen.
final Provider<GoRouter> routerProvider = Provider<GoRouter>(
  (ref) => buildRouter(
    initialLocation: ref.read(wipeNoticeProvider)
        ? AppRoutes.signedOut
        : ref.read(signedInProvider)
        ? AppRoutes.home
        : AppRoutes.language,
  ),
);

/// Builds the router; tests override [routerProvider] to start elsewhere.
GoRouter buildRouter({String initialLocation = AppRoutes.language}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.language,
        builder: (context, state) => const LanguageScreen(),
      ),
      GoRoute(
        path: AppRoutes.phone,
        builder: (context, state) => const PhoneScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) => const OtpScreen(),
      ),
      GoRoute(
        path: AppRoutes.consent,
        builder: (context, state) => const ConsentScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.cropDoctor,
        builder: (context, state) => const CropDoctorPlaceholderScreen(),
      ),
      GoRoute(
        path: AppRoutes.shop,
        builder: (context, state) => const ShopScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':skuId',
            builder: (context, state) =>
                ProductDetailScreen(skuId: state.pathParameters['skuId']!),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.cart,
        builder: (context, state) => const CartScreen(),
        routes: <RouteBase>[
          GoRoute(path: 'pay', builder: (context, state) => const PayScreen()),
        ],
      ),
      GoRoute(
        path: AppRoutes.orders,
        builder: (context, state) => const MyOrdersScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                OrderTrackingScreen(orderId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.crops,
        builder: (context, state) => const MyCropsScreen(),
      ),
      GoRoute(
        path: AppRoutes.khata,
        builder: (context, state) => const KhataScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'receipt',
            builder: (context, state) => PaymentReceiptScreen(
              receipt: state.extra is PaymentReceipt
                  ? state.extra! as PaymentReceipt
                  : null,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.visitScan,
        builder: (context, state) => const VisitScanScreen(),
      ),
      GoRoute(
        path: '/visit/:visitId',
        builder: (context, state) =>
            VisitConfirmScreen(visitId: state.pathParameters['visitId']!),
        routes: <RouteBase>[
          GoRoute(
            path: 'rate',
            builder: (context, state) => VisitRatingScreen(
              visitId: state.pathParameters['visitId']!,
              token: state.extra is ConfirmToken
                  ? state.extra! as ConfirmToken
                  : null,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.officer,
        builder: (context, state) => const OfficerScreen(),
      ),
      GoRoute(
        path: AppRoutes.me,
        builder: (context, state) => const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'consent',
            builder: (context, state) => const ConsentSettingsScreen(),
          ),
          GoRoute(
            path: 'delete',
            builder: (context, state) => const DeleteAccountScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.signedOut,
        builder: (context, state) => Consumer(
          builder: (context, ref, _) => SignedOutScreen(
            onSignInAgain: () async {
              await clearWipeNotice(ref.read(appDatabaseProvider));
              if (context.mounted) context.go(AppRoutes.language);
            },
          ),
        ),
      ),
    ],
  );
}
