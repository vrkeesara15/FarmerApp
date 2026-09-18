import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Full-width banner shown while the device is offline
/// (SPEC 13.1 `OfflineBanner`, NF-002).
class OfflineBanner extends StatelessWidget {
  /// Creates the banner.
  const OfflineBanner({this.message, super.key});

  /// Override for the default message.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space4,
          vertical: Tokens.space2,
        ),
        decoration: BoxDecoration(
          color: app.tint(p.statusWarningContainer),
          border: Border(
            bottom: BorderSide(color: p.statusWarning, width: app.borderWidth),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, color: p.statusWarning),
            const SizedBox(width: Tokens.space2),
            Expanded(
              child: Text(
                message ?? l10n.offlineBanner,
                style: app.text.label.copyWith(color: p.statusWarning),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
