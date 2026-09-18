import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/generated/core_localizations.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_models.dart';
import '../sync/sync_providers.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../utils/format.dart';
import 'app_button.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'sync_status_pill.dart';

/// Localised entity label for a sync item.
String syncEntityLabel(CoreLocalizations l10n, String entity) =>
    switch (entity) {
      SyncEntities.farmer => l10n.syncEntityFarmer,
      SyncEntities.farm => l10n.syncEntityFarm,
      SyncEntities.cropPlot => l10n.syncEntityCropPlot,
      SyncEntities.consentRecord => l10n.syncEntityConsent,
      SyncEntities.dutySession => l10n.syncEntityDutySession,
      SyncEntities.locationBatch => l10n.syncEntityLocationBatch,
      SyncEntities.policyAcceptance => l10n.syncEntityPolicyAcceptance,
      SyncEntities.visit => l10n.syncEntityVisit,
      SyncEntities.visitPhoto => l10n.syncEntityVisitPhoto,
      SyncEntities.visitConfirmation => l10n.syncEntityVisitConfirmation,
      SyncEntities.order => l10n.syncEntityOrder,
      SyncEntities.payment => l10n.syncEntityPayment,
      _ => l10n.syncEntityOther,
    };

/// Localised action label for a sync item.
String syncActionLabel(CoreLocalizations l10n, SyncAction action) =>
    switch (action) {
      SyncAction.create => l10n.syncActionCreate,
      SyncAction.update => l10n.syncActionUpdate,
      SyncAction.delete => l10n.syncActionDelete,
    };

/// A64 Sync details: status, last sync time, "Sync now", items waiting to
/// sync, items the server rejected with the error and Retry / Discard
/// (SPEC 13.2 "A64 Sync details (pending items, failed items with retry)").
class SyncDetailsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SyncDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final details = ref.watch(syncDetailsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncDetailsTitle)),
      body: SafeArea(
        child: details.when(
          data: (d) => _Body(details: d),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(syncDetailsProvider)),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.details});

  final SyncDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final engine = ref.read(syncEngineProvider);
    final status = details.status;
    final lastSync = details.lastSyncAt;
    final nothing =
        details.pending.isEmpty &&
        details.failed.isEmpty &&
        details.pendingUploads == 0 &&
        details.failedUploads == 0;
    return ListView(
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      children: <Widget>[
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SyncStatusPill(
                    state: status.pillState,
                    pendingCount: status.pending,
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space3),
              Text(
                lastSync == null
                    ? l10n.syncNeverSynced
                    : l10n.syncLastSync(formatDateTimeIst(lastSync)),
                style: app.text.body,
              ),
              if (details.lastError != null) ...<Widget>[
                const SizedBox(height: Tokens.space2),
                Text(
                  l10n.syncTransportError,
                  style: app.text.body.copyWith(
                    color: app.palette.statusWarning,
                  ),
                ),
                if (details.nextAttemptAt != null)
                  Text(
                    l10n.syncNextAttempt(
                      formatDateTimeIst(details.nextAttemptAt!),
                    ),
                    style: app.text.caption,
                  ),
              ],
              const SizedBox(height: Tokens.space4),
              AppButton(
                key: const Key('sync-now'),
                label: l10n.syncNow,
                icon: Icons.sync,
                loading: status.kind == SyncStatusKind.syncing,
                onPressed: engine.syncNow,
              ),
            ],
          ),
        ),
        if (nothing) ...<Widget>[
          const SizedBox(height: Tokens.space6),
          EmptyState(
            icon: Icons.cloud_done_outlined,
            title: l10n.syncAllDone,
            help: l10n.syncAllDoneHelp,
          ),
        ],
        if (details.failed.isNotEmpty || details.failedUploads > 0) ...<Widget>[
          const SizedBox(height: Tokens.space6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.syncFailedSection(
                    details.failed.length + details.failedUploads,
                  ),
                  style: app.text.heading,
                ),
              ),
              AppButton(
                key: const Key('sync-retry-all'),
                label: l10n.syncRetryAll,
                variant: AppButtonVariant.tertiary,
                size: AppButtonSize.medium,
                expand: false,
                onPressed: engine.retryAll,
              ),
            ],
          ),
          const SizedBox(height: Tokens.space2),
          for (final item in details.failed)
            _ItemTile(
              item: item,
              failed: true,
              onRetry: () => engine.retry(item.opId),
              onDiscard: () => engine.discard(item.opId),
            ),
        ],
        if (details.pending.isNotEmpty ||
            details.pendingUploads > 0) ...<Widget>[
          const SizedBox(height: Tokens.space6),
          Text(
            l10n.syncPendingSection(
              details.pending.length + details.pendingUploads,
            ),
            style: app.text.heading,
          ),
          if (details.pendingUploads > 0) ...<Widget>[
            const SizedBox(height: Tokens.space1),
            Text(
              l10n.syncPhotoUploads(details.pendingUploads),
              style: app.text.caption,
            ),
          ],
          const SizedBox(height: Tokens.space2),
          for (final item in details.pending) _ItemTile(item: item),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Material(
      color: app.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: app.borderSide,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space4),
        child: child,
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    this.failed = false,
    this.onRetry,
    this.onDiscard,
  });

  final SyncItem item;
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final title = l10n.syncItemTitle(
      syncActionLabel(l10n, item.action),
      syncEntityLabel(l10n, item.entity),
    );
    final detail = item.error?.detail;
    final subtitle = failed
        ? (detail == null || detail.isEmpty ? l10n.syncRejectedDefault : detail)
        : item.waitingForUpload
        ? l10n.syncWaitingForPhoto
        : l10n.syncSavedAt(formatDateTimeIst(item.clientTs));
    final color = failed ? p.statusDanger : p.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      child: _Card(
        child: Semantics(
          label: '$title, $subtitle',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    failed
                        ? Icons.error_outline
                        : item.waitingForUpload
                        ? Icons.photo_outlined
                        : Icons.schedule_outlined,
                    size: Tokens.space6,
                    color: color,
                  ),
                  const SizedBox(width: Tokens.space2),
                  Expanded(child: Text(title, style: app.text.label)),
                ],
              ),
              const SizedBox(height: Tokens.space1),
              Text(subtitle, style: app.text.body.copyWith(color: color)),
              if (failed) ...<Widget>[
                const SizedBox(height: Tokens.space3),
                Wrap(
                  spacing: Tokens.space2,
                  runSpacing: Tokens.space2,
                  children: <Widget>[
                    AppButton(
                      key: Key('sync-retry-${item.opId}'),
                      label: l10n.actionRetry,
                      icon: Icons.refresh,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      expand: false,
                      onPressed: onRetry,
                    ),
                    AppButton(
                      key: Key('sync-discard-${item.opId}'),
                      label: l10n.syncDiscard,
                      variant: AppButtonVariant.tertiary,
                      size: AppButtonSize.medium,
                      expand: false,
                      onPressed: onDiscard,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
