import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

/// A01 Splash with the tenant's logo and app name (FA-008); moves on after
/// a short delay.
///
/// The brand is read from the cache before the first frame
/// (`brandingOverrides`), so this screen is already the tenant's on a cold
/// start with no network.
class SplashScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SplashScreen({super.key});

  /// How long the splash stays before navigating.
  static const Duration hold = Duration(milliseconds: 900);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen.hold, () {
      if (mounted) context.go(AppRoutes.language);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BrandLogo(key: Key('splash-logo'), size: Tokens.space12 * 2),
            const SizedBox(height: Tokens.space4),
            Text(
              ref.watch(appBrandProvider).name(l10n),
              key: const Key('splash-app-name'),
              style: app.text.display,
            ),
            const SizedBox(height: Tokens.space2),
            Text(
              l10n.splashTagline,
              style: app.text.body.copyWith(color: app.palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
