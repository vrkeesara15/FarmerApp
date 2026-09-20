import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/advisory_widgets.dart';
import '../../widgets/kisan_widgets.dart';

/// FA-007 in-app inbox: every notification the server made for this
/// farmer, newest first, unread ones marked. Tapping a row marks it read
/// and opens its deep link (F27 result, order tracking, alerts, the crop
/// calendar, the visit question). Works offline from the cache.
class InboxScreen extends ConsumerWidget {
  /// Creates the screen.
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final rows = ref.watch(inboxProvider).value ?? const <AppNotification>[];
    final unread = rows.where((n) => n.unread).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inboxTitle),
        actions: <Widget>[
          if (unread > 0)
            TextButton.icon(
              key: const Key('inbox-read-all'),
              onPressed: () =>
                  ref.read(advisoryRepositoryProvider).markAllRead(),
              icon: const Icon(Icons.done_all),
              label: Text(l10n.inboxMarkAllRead),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: RefreshOnOpen(
                onOpen: (ref) =>
                    ref.read(advisoryRepositoryProvider).refreshInbox(),
                child: rows.isEmpty
                    ? EmptyState(
                        icon: Icons.mark_email_unread_outlined,
                        title: l10n.inboxEmpty,
                        help: l10n.inboxEmptyHelp,
                      )
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(advisoryRepositoryProvider).refreshInbox(),
                        child: ListView(
                          padding: const EdgeInsets.all(
                            Tokens.spaceScreenPadding,
                          ),
                          children: <Widget>[
                            if (unread > 0)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Tokens.space2,
                                ),
                                child: Text(
                                  l10n.inboxUnread(unread),
                                  key: const Key('inbox-unread'),
                                  style: app.text.label,
                                ),
                              ),
                            for (final row in rows)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Tokens.space2,
                                ),
                                child: _InboxRow(notification: row),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxRow extends ConsumerWidget {
  const _InboxRow({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final (title, body) = notificationCopy(l10n, notification);
    return Card(
      key: Key('inbox-${notification.id}'),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: Tokens.sizeTouchTargetMin,
        leading: Icon(
          notificationIcon(notification.kind),
          color: notification.unread ? p.primary : p.textSecondary,
        ),
        title: Text(
          title,
          style: app.text.label.copyWith(
            fontWeight: notification.unread ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(body, style: app.text.body),
            Text(
              formatDateTimeIst(notification.createdAt),
              style: app.text.caption.copyWith(color: p.textSecondary),
            ),
          ],
        ),
        trailing: notification.unread
            ? Icon(
                Icons.circle,
                key: Key('inbox-unread-${notification.id}'),
                size: Tokens.space3,
                color: p.primary,
              )
            : null,
        onTap: () async {
          await ref.read(advisoryRepositoryProvider).markRead(notification.id);
          if (!context.mounted) return;
          final route = farmerDeepLink(
            kind: notification.kind,
            route: notification.route,
            data: notification.data,
          );
          if (route != null) unawaited(context.push<void>(route));
        },
      ),
    );
  }
}
