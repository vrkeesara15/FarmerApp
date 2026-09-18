import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/language_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/phone_screen.dart';
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
}

/// The app router.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
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
    ],
  );
});
