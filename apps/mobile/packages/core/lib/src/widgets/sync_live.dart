import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_engine.dart';
import '../sync/sync_providers.dart';
import 'offline_banner.dart';
import 'sync_status_pill.dart';

/// [SyncStatusPill] driven by [syncStatusProvider] (A10 home, A63).
class SyncStatusPillLive extends ConsumerWidget {
  /// Creates the pill.
  const SyncStatusPillLive({this.onTap, super.key});

  /// Opens A64 sync details.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ?? SyncStatus.synced;
    return SyncStatusPill(
      state: status.pillState,
      pendingCount: status.pending,
      onTap: onTap,
    );
  }
}

/// [OfflineBanner] shown only while [offlineProvider] is true (NF-002).
class OfflineBannerLive extends ConsumerWidget {
  /// Creates the banner.
  const OfflineBannerLive({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider);
    return offline ? const OfflineBanner() : const SizedBox.shrink();
  }
}
