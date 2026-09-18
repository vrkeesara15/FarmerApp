import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// F70 Me: language and theme (Light/Sunlight).
///
/// Notifications, consent settings, help, delete account and about rows
/// arrive with their own requirement IDs (FA-007, FM-002, FM-015).
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final sunlight = settings.themeMode == AppThemeMode.sunlight;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          children: <Widget>[
            LanguageSettingTile(
              value: settings.locale,
              onChanged: notifier.setLocale,
              onPlayAudio: (_) {
                // Audio prompts are bundled per language with the FM audio
                // assets; playback is wired with that requirement.
              },
            ),
            const SizedBox(height: Tokens.space3),
            Material(
              color: app.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusCard),
                side: app.borderSide,
              ),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                key: const Key('theme-setting'),
                secondary: Icon(
                  sunlight ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                  color: app.palette.primary,
                ),
                title: Text(l10n.settingsTheme, style: app.text.label),
                subtitle: Text(
                  sunlight ? l10n.themeSunlight : l10n.themeLight,
                  style: app.text.body,
                ),
                value: sunlight,
                onChanged: (on) => notifier.setThemeMode(
                  on ? AppThemeMode.sunlight : AppThemeMode.light,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
