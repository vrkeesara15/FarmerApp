import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'app_button.dart';

/// Error illustration + message + retry (SPEC 13.1 `ErrorState`).
class ErrorState extends StatelessWidget {
  /// Creates the state.
  const ErrorState({this.title, this.help, this.onRetry, super.key});

  /// Title; defaults to "Something went wrong".
  final String? title;

  /// Help text; defaults to a connectivity hint.
  final String? help;

  /// Retry handler; the button is hidden when `null`.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(Tokens.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: Tokens.space12 * 2,
            height: Tokens.space12 * 2,
            decoration: BoxDecoration(
              color: app.tint(p.statusDangerContainer),
              shape: BoxShape.circle,
              border: Border.all(color: p.statusDanger, width: app.borderWidth),
            ),
            child: Icon(
              Icons.error_outline,
              size: Tokens.space12,
              color: p.statusDanger,
            ),
          ),
          const SizedBox(height: Tokens.space4),
          Text(
            title ?? l10n.errorTitle,
            textAlign: TextAlign.center,
            style: app.text.heading,
          ),
          const SizedBox(height: Tokens.space2),
          Text(
            help ?? l10n.errorHelp,
            textAlign: TextAlign.center,
            style: app.text.body.copyWith(color: p.textSecondary),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: Tokens.space6),
            AppButton(
              label: l10n.actionRetry,
              icon: Icons.refresh,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
