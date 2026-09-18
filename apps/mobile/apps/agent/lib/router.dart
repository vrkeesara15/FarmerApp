import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/farmers/add_farmer_wizard_screen.dart';
import 'screens/farmers/farm_edit_screen.dart';
import 'screens/farmers/farmer_list_screen.dart';
import 'screens/farmers/farmer_profile_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/home/my_day_screen.dart';
import 'screens/language_screen.dart';
import 'screens/onboarding/device_registered_screen.dart';
import 'screens/onboarding/disclosure_screen.dart';
import 'screens/onboarding/permissions_screen.dart';
import 'screens/otp_screen.dart';
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
