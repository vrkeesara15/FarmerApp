import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Outbox sync state (NF-003).
enum SyncState {
  /// Everything is uploaded.
  synced,

  /// Items are waiting to upload.
  pending,

  /// The last attempt failed.
  failed,
}

/// Small pill showing synced / pending n / failed
/// (SPEC 13.1 `SyncStatusPill`).
class SyncStatusPill extends StatelessWidget {
  /// Creates the pill.
  const SyncStatusPill({
    required this.state,
    this.pendingCount = 0,
    this.onTap,
    super.key,
  });

  /// Current state.
  final SyncState state;

  /// Number of queued items (shown when [state] is [SyncState.pending]).
  final int pendingCount;

  /// Optional tap handler (opens sync details).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final (
      Color color,
      Color container,
      IconData icon,
      String label,
    ) = switch (state) {
      SyncState.synced => (
        p.statusSuccess,
        app.tint(p.statusSuccessContainer),
        Icons.cloud_done_outlined,
        l10n.syncSynced,
      ),
      SyncState.pending => (
        p.statusWarning,
        app.tint(p.statusWarningContainer),
        Icons.cloud_upload_outlined,
        l10n.syncPending(pendingCount),
      ),
      SyncState.failed => (
        p.statusDanger,
        app.tint(p.statusDangerContainer),
        Icons.cloud_off_outlined,
        l10n.syncFailed,
      ),
    };
    return Semantics(
      button: onTap != null,
      label: label,
      child: Material(
        color: container,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
          side: BorderSide(color: color, width: app.borderWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.space3,
              vertical: Tokens.space1,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: Tokens.space4, color: color),
                const SizedBox(width: Tokens.space1),
                Flexible(
                  child: Text(
                    label,
                    style: app.text.label.copyWith(color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
