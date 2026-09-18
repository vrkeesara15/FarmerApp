import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/language_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/phone_screen.dart';

/// Route paths for the onboarding shells (SPEC 13.3).
abstract final class AppRoutes {
  /// F01 Language picker with audio.
  static const String language = '/';

  /// F02 Phone login.
  static const String phone = '/login';

  /// F03 OTP.
  static const String otp = '/login/otp';
}

/// The app router.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.language,
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
    ],
  );
});
