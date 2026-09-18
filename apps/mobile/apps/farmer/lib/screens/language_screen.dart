import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/theme_toggle_action.dart';

/// F01 Language picker with audio. Low-literacy first screen: big title,
/// audio hint with speaker icon, one primary action.
class LanguageScreen extends ConsumerWidget {
  /// Creates the screen.
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appNameFarmer),
        actions: const <Widget>[ThemeToggleAction()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l10n.languagePickerTitle, style: app.text.display),
              const SizedBox(height: Tokens.space2),
              Row(
                children: <Widget>[
                  Icon(Icons.volume_up_outlined, color: app.palette.primary),
                  const SizedBox(width: Tokens.space2),
                  Expanded(
                    child: Text(
                      l10n.languagePickerSubtitle,
                      style: app.text.body.copyWith(
                        color: app.palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space4),
              Expanded(
                child: SingleChildScrollView(
                  child: LanguagePicker(
                    selected: settings.locale,
                    onSelected: ref.read(settingsProvider.notifier).setLocale,
                    onPlayAudio: (_) {
                      // Audio prompts are bundled per language with FM audio
                      // assets; playback is wired with that requirement.
                    },
                  ),
                ),
              ),
              const SizedBox(height: Tokens.space4),
              AppButton(
                label: l10n.actionContinue,
                icon: Icons.arrow_forward,
                onPressed: settings.locale == null
                    ? null
                    : () => context.go(AppRoutes.phone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
