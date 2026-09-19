import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/kisan_widgets.dart';
import '../widgets/theme_toggle_action.dart';

/// F01 Language picker with audio (FM-001). Low-literacy first screen: big
/// title, a speaker that reads the instruction, five tiles each with a
/// speaker that says the short prompt in that language, one primary
/// action. One decision on the screen.
class LanguageScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  final Set<String> _unavailable = <String>{};

  @override
  void initState() {
    super.initState();
    _checkVoices();
  }

  Future<void> _checkVoices() async {
    final audio = ref.read(audioPromptProvider);
    final missing = <String>{};
    for (final o in LanguageOption.launchLanguages) {
      if (!await audio.isAvailable(o.locale)) {
        missing.add(o.locale.languageCode);
      }
    }
    if (mounted && missing.isNotEmpty) {
      setState(() => _unavailable.addAll(missing));
    }
  }

  Future<void> _play(Locale locale) async {
    final own = lookupCoreLocalizations(locale);
    final result = await ref
        .read(audioPromptProvider)
        .play(
          promptId: 'f01_language',
          text: own.kisanLanguagePrompt,
          locale: locale,
        );
    if (!mounted || result == AudioPlayResult.played) return;
    setState(() => _unavailable.add(locale.languageCode));
    showKisanMessage(context, CoreLocalizations.of(context).audioUnavailable);
  }

  @override
  Widget build(BuildContext context) {
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
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AudioButton(
                  promptId: 'f01_choose_language',
                  text:
                      '${l10n.languagePickerTitle}. '
                      '${l10n.languagePickerSubtitle}',
                  label: l10n.languagePickerSubtitle,
                ),
              ),
              const SizedBox(height: Tokens.space2),
              Expanded(
                child: SingleChildScrollView(
                  child: LanguagePicker(
                    selected: settings.locale,
                    onSelected: ref.read(settingsProvider.notifier).setLocale,
                    onPlayAudio: _play,
                    audioUnavailable: _unavailable,
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
