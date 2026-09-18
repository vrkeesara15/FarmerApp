import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

/// A01 Splash with tenant logo placeholder; moves on after a short delay.
class SplashScreen extends StatefulWidget {
  /// Creates the screen.
  const SplashScreen({super.key});

  /// How long the splash stays before navigating.
  static const Duration hold = Duration(milliseconds: 900);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
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
            Container(
              width: Tokens.space12 * 2,
              height: Tokens.space12 * 2,
              decoration: BoxDecoration(
                color: app.tint(app.palette.primaryContainer),
                shape: BoxShape.circle,
                border: Border.fromBorderSide(app.borderSide),
              ),
              child: Icon(
                Icons.eco_outlined,
                size: Tokens.space12,
                color: app.palette.primary,
              ),
            ),
            const SizedBox(height: Tokens.space4),
            Text(l10n.appNameAgent, style: app.text.display),
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
