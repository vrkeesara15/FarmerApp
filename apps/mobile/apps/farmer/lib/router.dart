import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/language_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/phone_screen.dart';
import 'screens/settings_screen.dart';

/// Route paths for the onboarding shells (SPEC 13.3).
abstract final class AppRoutes {
  /// F01 Language picker with audio.
  static const String language = '/';

  /// F02 Phone login.
  static const String phone = '/login';

  /// F03 OTP.
  static const String otp = '/login/otp';

  /// F70 Me.
  static const String settings = '/me';

  /// Signed out by your administrator (SEC-025; the officer app's A08).
  static const String signedOut = '/signed-out';
}

/// The app router; after a remote wipe it opens on the signed-out screen.
final Provider<GoRouter> routerProvider = Provider<GoRouter>(
  (ref) => buildRouter(
    initialLocation: ref.read(wipeNoticeProvider)
        ? AppRoutes.signedOut
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
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
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
