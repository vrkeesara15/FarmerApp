import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'app_button.dart';

/// Illustration + one-line help + optional action (SPEC 13.1 `EmptyState`).
class EmptyState extends StatelessWidget {
  /// Creates the state.
  const EmptyState({
    this.icon = Icons.inbox_outlined,
    this.title,
    this.help,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Pictogram standing in for the illustration.
  final IconData icon;

  /// Title; defaults to "Nothing here yet".
  final String? title;

  /// One-line help.
  final String? help;

  /// Action button label; shown only with [onAction].
  final String? actionLabel;

  /// Action handler.
  final VoidCallback? onAction;

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
              color: app.tint(p.primaryContainer),
              shape: BoxShape.circle,
              border: Border.fromBorderSide(app.borderSide),
            ),
            child: Icon(icon, size: Tokens.space12, color: p.primary),
          ),
          const SizedBox(height: Tokens.space4),
          Text(
            title ?? l10n.emptyDefaultTitle,
            textAlign: TextAlign.center,
            style: app.text.heading,
          ),
          const SizedBox(height: Tokens.space2),
          Text(
            help ?? l10n.emptyDefaultHelp,
            textAlign: TextAlign.center,
            style: app.text.body.copyWith(color: p.textSecondary),
          ),
          if (onAction != null && actionLabel != null) ...<Widget>[
            const SizedBox(height: Tokens.space6),
            AppButton(
              label: actionLabel!,
              icon: Icons.add,
              size: AppButtonSize.medium,
              expand: false,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
