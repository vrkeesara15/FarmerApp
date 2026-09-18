import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';

/// A07 Device registered: success and the way to A10 Home.
class DeviceRegisteredScreen extends StatelessWidget {
  /// Creates the screen.
  const DeviceRegisteredScreen({super.key});

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
            children: <Widget>[
              const Spacer(),
              Container(
                width: Tokens.space12 * 2,
                height: Tokens.space12 * 2,
                decoration: BoxDecoration(
                  color: app.tint(p.statusSuccessContainer),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: p.statusSuccess,
                    width: app.borderWidth,
                  ),
                ),
                child: Icon(
                  Icons.verified_outlined,
                  size: Tokens.space12,
                  color: p.statusSuccess,
                ),
              ),
              const SizedBox(height: Tokens.space6),
              Text(
                l10n.registeredTitle,
                style: app.text.display,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Tokens.space2),
              Text(
                l10n.registeredBody,
                style: app.text.body.copyWith(color: p.textSecondary),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              AppButton(
                key: const Key('registered-start'),
                label: l10n.registeredStart,
                icon: Icons.home_outlined,
                onPressed: () => context.go(AppRoutes.home),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
