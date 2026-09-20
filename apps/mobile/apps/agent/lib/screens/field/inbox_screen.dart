import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'field_widgets.dart';

/// A13 Notifications inbox (FA-007).
///
/// The list is the local `notification` sync entity, so it opens offline;
/// opening the screen also pulls `GET /v1/notifications` in the background.
/// Tapping a row marks it read (through the outbox) and follows the row's
/// deep link — the same route an FCM tap uses.
class InboxScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(fieldRepositoryProvider).refreshInbox());
  }

  Future<void> _open(InboxItem item) async {
    await ref.read(fieldRepositoryProvider).markRead(item.id);
    if (!mounted) return;
    unawaited(context.push(deepLinkFor(item.route)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final inbox = ref.watch(inboxProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inboxTitle),
        actions: <Widget>[
          if ((inbox.value?.unread ?? 0) > 0)
            TextButton(
              key: const Key('inbox-mark-all-read'),
              onPressed: () =>
                  unawaited(ref.read(fieldRepositoryProvider).markAllRead()),
              child: Text(l10n.inboxMarkAllRead),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: inbox.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    ErrorState(onRetry: () => ref.invalidate(inboxProvider)),
                data: (data) => data.isEmpty
                    ? EmptyState(
                        key: const Key('inbox-empty'),
                        icon: Icons.notifications_none_outlined,
                        title: l10n.inboxEmpty,
                        help: l10n.inboxEmptyHelp,
                      )
                    : ListView(
                        padding: const EdgeInsets.all(
                          Tokens.spaceScreenPadding,
                        ),
                        children: <Widget>[
                          if (data.unread > 0)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: Tokens.space2,
                              ),
                              child: FieldCaption(
                                l10n.inboxUnread(data.unread),
                                icon: Icons.mark_email_unread_outlined,
                                color: p.primary,
                              ),
                            ),
                          for (final item in data.items)
                            FieldCard(
                              key: Key('inbox-item-${item.id}'),
                              color: item.unread
                                  ? app.tint(p.primaryContainer)
                                  : p.surface,
                              onTap: () => unawaited(_open(item)),
                              child: ListTile(
                                leading: Icon(
                                  _iconFor(item.kind),
                                  color: item.unread
                                      ? p.primary
                                      : p.textSecondary,
                                ),
                                title: Text(
                                  NotificationCopy.title(l10n, item),
                                  style: app.text.label,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      NotificationCopy.body(l10n, item),
                                      style: app.text.body,
                                    ),
                                    const SizedBox(height: Tokens.space1),
                                    FieldCaption(
                                      formatDateTimeIst(item.createdAt),
                                    ),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String kind) => switch (kind) {
    'beat_plan_ready' => Icons.map_outlined,
    'order_status' => Icons.shopping_bag_outlined,
    'credit_approval_decided' => Icons.account_balance_outlined,
    'travel_claim_submitted' ||
    'travel_claim_decided' => Icons.receipt_long_outlined,
    'flag_assigned' || 'flag_escalated' => Icons.flag_outlined,
    'duty_auto_ended' => Icons.work_off_outlined,
    'diagnosis_ready' ||
    'diagnosis_reviewed' ||
    'diagnosis_expert_requested' => Icons.eco_outlined,
    'visit_confirm_request' => Icons.verified_outlined,
    _ => Icons.notifications_none_outlined,
  };
}
