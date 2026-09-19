import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'app_button.dart';

/// A08 "Signed out by your administrator" (SEC-025): shown after a remote
/// wipe, in both apps, until the user taps "Sign in again". Neutral
/// warning tone: nothing the user did wrong, no blame, no error code.
class SignedOutScreen extends StatelessWidget {
  /// Creates the screen.
  const SignedOutScreen({required this.onSignInAgain, super.key});

  /// Clears the notice and goes to the language / phone step.
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: Tokens.space12),
                      Semantics(
                        excludeSemantics: true,
                        child: Container(
                          width: Tokens.space12 * 2,
                          height: Tokens.space12 * 2,
                          decoration: BoxDecoration(
                            color: app.tint(p.statusWarningContainer),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: p.statusWarning,
                              width: app.borderWidth,
                            ),
                          ),
                          child: Icon(
                            Icons.phonelink_lock_outlined,
                            size: Tokens.space12,
                            color: p.statusWarning,
                          ),
                        ),
                      ),
                      const SizedBox(height: Tokens.space6),
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.wipeTitle,
                          key: const Key('wipe-title'),
                          style: app.text.display,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: Tokens.space4),
                      Text(
                        l10n.wipeBody,
                        style: app.text.body,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Tokens.space4),
                      Text(
                        l10n.wipeDeletedList,
                        style: app.text.body.copyWith(color: p.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Tokens.space4),
                      Text(
                        l10n.wipeWhatNext,
                        style: app.text.body.copyWith(color: p.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Tokens.space4),
              AppButton(
                key: const Key('wipe-sign-in'),
                label: l10n.wipeSignInAgain,
                icon: Icons.login,
                onPressed: onSignInAgain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown for the second the wipe takes (the app's providers are already
/// torn down, so no theme or localisation is available): a spinner on the
/// light surface, no text.
class WipeInProgressView extends StatelessWidget {
  /// Creates the view.
  const WipeInProgressView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFFFFFFFF),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
