import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/farmers/add_farmer_wizard_screen.dart';
import 'screens/farmers/farm_edit_screen.dart';
import 'screens/farmers/farmer_list_screen.dart';
import 'screens/farmers/farmer_profile_screen.dart';
import 'screens/language_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/phone_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';

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
