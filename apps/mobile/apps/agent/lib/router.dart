import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/farmers/add_farmer_wizard_screen.dart';
import 'screens/farmers/farm_edit_screen.dart';
import 'screens/farmers/farmer_list_screen.dart';
import 'screens/farmers/farmer_profile_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/home/my_day_screen.dart';
import 'screens/khata/khata_screen.dart';
import 'screens/language_screen.dart';
import 'screens/onboarding/device_registered_screen.dart';
import 'screens/onboarding/disclosure_screen.dart';
import 'screens/onboarding/permissions_screen.dart';
import 'screens/orders/cart_screen.dart';
import 'screens/orders/catalog_screen.dart';
import 'screens/orders/commerce_copy.dart';
import 'screens/orders/order_screen.dart';
import 'screens/orders/orders_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/payments/cash_screen.dart';
import 'screens/payments/checkout_screen.dart';
import 'screens/payments/collections_screen.dart';
import 'screens/payments/credit_screen.dart';
import 'screens/payments/link_screen.dart';
import 'screens/payments/upi_screen.dart';
import 'screens/phone_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/visits/confirm_screen.dart';
import 'screens/visits/start_visit_screen.dart';
import 'screens/visits/summary_screen.dart';
import 'screens/visits/visit_screen.dart';
import 'screens/visits/visits_list_screen.dart';

/// Route paths (SPEC 13.2).
abstract final class AppRoutes {
  /// A01 Splash.
  static const String splash = '/';

  /// A02 Language picker.
  static const String language = '/language';

  /// A03 Phone login.
  static const String phone = '/login';

  /// A04 OTP entry.
  static const String otp = '/login/otp';

  /// A05 Location and data disclosure (first run).
  static const String disclosure = '/onboarding/disclosure';

  /// A06 Permissions explainer.
  static const String permissions = '/onboarding/permissions';

  /// A07 Device registered.
  static const String registered = '/onboarding/done';

  /// A10 Home.
  static const String home = '/home';

  /// A12 My day timeline.
  static const String myDay = '/home/day';

  /// A05 again, from Home "Review policy" (FA-011 newer version).
  static const String policy = '/home/policy';

  /// A20 Farmer list.
  static const String farmers = '/farmers';

  /// A21 Add farmer wizard.
  static const String addFarmer = '/farmers/new';

  /// A22 Farmer profile.
  static String farmerPath(String id) => '/farmers/$id';

  /// A23 Add a farm to a farmer.
  static String addFarmPath(String farmerId) => '/farmers/$farmerId/farms/new';

  /// A23 Edit a farm.
  static String editFarmPath(String farmerId, String farmId) =>
      '/farmers/$farmerId/farms/$farmId';

  /// A34 Visits list (A30–A33 paths in `VisitRoutes`).
  static const String visits = '/visits';

  /// A63 Profile and settings.
  static const String settings = '/settings';

  /// A64 Sync details (under Me / settings).
  static const String syncDetails = '/settings/sync';
}

/// The app router.
final Provider<GoRouter> routerProvider = Provider<GoRouter>(
  (ref) => buildRouter(),
);

/// Builds the router; tests override [routerProvider] to start elsewhere.
GoRouter buildRouter({String initialLocation = AppRoutes.splash}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
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
        path: AppRoutes.disclosure,
        builder: (context, state) => const DisclosureScreen(),
      ),
      GoRoute(
        path: AppRoutes.permissions,
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.registered,
        builder: (context, state) => const DeviceRegisteredScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'day',
            builder: (context, state) => const MyDayScreen(),
          ),
          GoRoute(
            path: 'policy',
            builder: (context, state) =>
                const DisclosureScreen(onboarding: false),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.farmers,
        builder: (context, state) => const FarmerListScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            builder: (context, state) => const AddFarmerWizardScreen(),
          ),
          GoRoute(
            path: ':farmerId',
            builder: (context, state) => FarmerProfileScreen(
              farmerId: state.pathParameters['farmerId']!,
            ),
            routes: <RouteBase>[
              GoRoute(
                path: 'farms/new',
                builder: (context, state) =>
                    FarmEditScreen(farmerId: state.pathParameters['farmerId']!),
              ),
              GoRoute(
                path: 'farms/:farmId',
                builder: (context, state) => FarmEditScreen(
                  farmerId: state.pathParameters['farmerId']!,
                  farmId: state.pathParameters['farmId'],
                ),
              ),
              // FA-022 A58 khata, FA-021 A52 in dues mode.
              GoRoute(
                path: 'khata',
                builder: (context, state) =>
                    KhataScreen(farmerId: state.pathParameters['farmerId']!),
              ),
              GoRoute(
                path: 'collect',
                builder: (context, state) => CheckoutScreen(
                  duesFarmerId: state.pathParameters['farmerId'],
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.visits,
        builder: (context, state) => const VisitsListScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            builder: (context, state) => StartVisitScreen(
              farmerId: state.uri.queryParameters['farmerId'],
              farmId: state.uri.queryParameters['farmId'],
            ),
          ),
          GoRoute(
            path: ':visitId',
            builder: (context, state) =>
                VisitScreen(visitId: state.pathParameters['visitId']!),
            routes: <RouteBase>[
              GoRoute(
                path: 'confirm',
                builder: (context, state) =>
                    ConfirmScreen(visitId: state.pathParameters['visitId']!),
              ),
              GoRoute(
                path: 'summary',
                builder: (context, state) =>
                    SummaryScreen(visitId: state.pathParameters['visitId']!),
              ),
            ],
          ),
        ],
      ),
      // FA-020 / FA-021: orders (A50, A51, A52, A57) and payments
      // (A53–A56), A59 collections.
      GoRoute(
        path: CommerceRoutes.orders,
        builder: (context, state) => const OrdersScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'pick',
            builder: (context, state) => FarmerPickerScreen(
              purpose: state.uri.queryParameters['for'] == 'collect'
                  ? PickPurpose.collect
                  : PickPurpose.order,
            ),
          ),
          GoRoute(
            path: 'new',
            builder: (context, state) {
              final farmerId = state.uri.queryParameters['farmerId'];
              return farmerId == null
                  ? const FarmerPickerScreen(purpose: PickPurpose.order)
                  : CatalogScreen(farmerId: farmerId);
            },
          ),
          GoRoute(
            path: 'cart',
            builder: (context, state) => const CartScreen(),
          ),
          GoRoute(
            path: 'checkout',
            builder: (context, state) => const CheckoutScreen(),
          ),
          GoRoute(
            path: ':orderId',
            builder: (context, state) =>
                OrderScreen(orderId: state.pathParameters['orderId']!),
          ),
        ],
      ),
      GoRoute(
        path: '/payments/cash',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return CashScreen(
            orderId: q['orderId'],
            farmerId: q['farmerId'],
            storeId: q['storeId'],
            amountPaise: int.tryParse(q['amount'] ?? ''),
          );
        },
      ),
      GoRoute(
        path: '/payments/:paymentId/upi',
        builder: (context, state) =>
            UpiScreen(paymentId: state.pathParameters['paymentId']!),
      ),
      GoRoute(
        path: '/payments/:paymentId/link',
        builder: (context, state) =>
            LinkScreen(paymentId: state.pathParameters['paymentId']!),
      ),
      GoRoute(
        path: '/payments/:paymentId/credit',
        builder: (context, state) =>
            CreditScreen(paymentId: state.pathParameters['paymentId']!),
      ),
      GoRoute(
        path: CommerceRoutes.collections,
        builder: (context, state) => const CollectionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'sync',
            builder: (context, state) => const SyncDetailsScreen(),
          ),
        ],
      ),
    ],
  );
}
