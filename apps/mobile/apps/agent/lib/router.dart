import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/language_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/phone_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';

/// Route paths for the onboarding shells (SPEC 13.2).
abstract final class AppRoutes {
  /// A01 Splash.
  static const String splash = '/';

  /// A02 Language picker.
  static const String language = '/language';

  /// A03 Phone login.
  static const String phone = '/login';

  /// A04 OTP entry.
  static const String otp = '/login/otp';

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
