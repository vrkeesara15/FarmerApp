import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/kisan_widgets.dart';

/// F70 "Delete my account" (FM-015): what happens (read aloud), a second
/// confirmation step, then `POST /v1/me/deletion-request`; afterwards the
/// ticket, its status and the due date (`GET /v1/me/deletion-request`).
class DeleteAccountScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  bool _confirming = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(kisanRepositoryProvider).refreshDeletion());
  }

  Future<void> _request() async {
    final l10n = CoreLocalizations.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(kisanRepositoryProvider)
        .requestDeletion(reason: 'farmer_app');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _confirming = false;
    });
    if (result == KisanWrite.offline) {
      showKisanMessage(context, l10n.kisanNeedsInternet);
    } else if (result == KisanWrite.refused) {
      showKisanMessage(context, l10n.kisanSaveFailed);
    }
  }

  String _status(CoreLocalizations l10n, String status) => switch (status) {
    'received' => l10n.kisanDeleteStatusReceived,
    'completed' => l10n.kisanDeleteStatusCompleted,
    'rejected' => l10n.kisanDeleteStatusRejected,
    _ => l10n.kisanDeleteStatusInProgress,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final ticket = ref.watch(kisanDeletionProvider).value;
    final Widget body;
    if (ticket != null) {
      body = Column(
        key: const Key('delete-ticket'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(Icons.mark_email_read_outlined, size: 72, color: p.primary),
          const SizedBox(height: Tokens.space3),
          Text(
            _status(l10n, ticket.status),
            key: const Key('delete-status'),
            textAlign: TextAlign.center,
            style: app.text.title,
          ),
          const SizedBox(height: Tokens.space3),
          Text(
            l10n.kisanDeleteTicket(ticket.shortTicket),
            key: const Key('delete-ticket-id'),
            textAlign: TextAlign.center,
            style: app.text.heading,
          ),
          if (ticket.dueBy != null)
            Text(
              l10n.kisanDeleteDueBy(formatDateIst(ticket.dueBy!)),
              key: const Key('delete-due'),
              textAlign: TextAlign.center,
              style: app.text.body,
            ),
          const SizedBox(height: Tokens.space3),
          SpokenText(promptId: 'f70_delete_after', text: l10n.kisanDeleteAfter),
        ],
      );
    } else if (_confirming) {
      body = Column(
        key: const Key('delete-confirm-step'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 72, color: p.statusDanger),
          const SizedBox(height: Tokens.space3),
          SpokenText(
            promptId: 'f70_delete_sure',
            text: l10n.kisanDeleteAreYouSure,
            style: app.text.title,
          ),
          const Spacer(),
          AppButton(
            key: const Key('delete-yes'),
            label: l10n.kisanDeleteYes,
            icon: Icons.delete_forever_outlined,
            variant: AppButtonVariant.destructive,
            loading: _busy,
            onPressed: _busy ? null : _request,
          ),
          const SizedBox(height: Tokens.space2),
          AppButton(
            key: const Key('delete-cancel'),
            label: l10n.kisanDeleteKeep,
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => setState(() => _confirming = false),
          ),
        ],
      );
    } else {
      body = Column(
        key: const Key('delete-explain'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              children: <Widget>[
                SpokenText(
                  promptId: 'f70_delete_explain',
                  text: l10n.kisanDeleteExplain,
                ),
                const SizedBox(height: Tokens.space2),
                Text(
                  l10n.kisanDeleteKeepsDues,
                  style: app.text.body.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          AppButton(
            key: const Key('delete-start'),
            label: l10n.kisanDeleteAccount,
            icon: Icons.delete_outline,
            variant: AppButtonVariant.destructive,
            onPressed: () => setState(() => _confirming = true),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanDeleteAccount)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: body,
        ),
      ),
    );
  }
}
