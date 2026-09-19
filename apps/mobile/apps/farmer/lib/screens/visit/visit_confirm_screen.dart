import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';

/// F60 Visit confirmation prompt (FM-011): "Did Ramesh visit your farm
/// today?" Yes / No, read aloud. The prompt comes from a push payload
/// (with the signed token) or the sync feed (`app_push` pending); without
/// a token "Yes" goes to the QR scan on the officer's phone.
class VisitConfirmScreen extends ConsumerWidget {
  /// Creates the screen.
  const VisitConfirmScreen({required this.visitId, super.key});

  /// Visit asked about.
  final String visitId;

  Future<void> _no(BuildContext context, WidgetRef ref) async {
    final l10n = CoreLocalizations.of(context);
    await ref.read(kisanRepositoryProvider).dismissPrompt(visitId);
    if (!context.mounted) return;
    showKisanMessage(context, l10n.kisanVisitNoThanks);
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final prompts = ref.watch(visitPromptsProvider).value;
    final prompt = prompts?.where((x) => x.visitId == visitId).firstOrNull;
    final officer = prompt?.officerFirstName;
    final question = officer == null
        ? l10n.kisanVisitQuestionNoName
        : l10n.kisanVisitQuestion(officer);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanVisitTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: Tokens.space6),
              CircleAvatar(
                radius: 48,
                backgroundColor: app.tint(p.primaryContainer),
                child: Icon(
                  Icons.person_pin_circle,
                  size: 56,
                  color: p.primary,
                ),
              ),
              const SizedBox(height: Tokens.space4),
              Text(
                question,
                key: const Key('visit-question'),
                textAlign: TextAlign.center,
                style: app.text.title,
              ),
              Center(
                child: AudioButton(promptId: 'f60_question', text: question),
              ),
              if (prompts != null && prompt == null)
                Text(
                  l10n.kisanVisitAlreadyAnswered,
                  textAlign: TextAlign.center,
                  style: app.text.body.copyWith(color: p.textSecondary),
                ),
              const Spacer(),
              AppButton(
                key: const Key('visit-yes'),
                label: l10n.kisanYes,
                icon: Icons.thumb_up_alt_outlined,
                onPressed: () {
                  final token = prompt?.token;
                  if (token == null) {
                    context.push(AppRoutes.visitScan);
                    return;
                  }
                  context.push(
                    AppRoutes.visitRate(visitId),
                    extra:
                        ConfirmToken.decode(token) ??
                        ConfirmToken(
                          raw: token,
                          visitId: visitId,
                          channel: prompt!.channel,
                        ),
                  );
                },
              ),
              const SizedBox(height: Tokens.space2),
              AppButton(
                key: const Key('visit-no'),
                label: l10n.kisanNo,
                icon: Icons.thumb_down_alt_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: () => _no(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
