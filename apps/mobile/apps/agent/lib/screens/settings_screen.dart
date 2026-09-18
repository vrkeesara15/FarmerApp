import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

/// A63 Profile and settings: language, theme (Light/Sunlight) and the sync
/// row (status pill, "Sync now", opens A64 Sync details).
///
/// The "Log out" row arrives with the session work.
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
            const SizedBox(height: Tokens.space3),
            Material(
              color: app.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusCard),
                side: app.borderSide,
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: const Key('sync-setting'),
                leading: Icon(Icons.sync, color: app.palette.primary),
                title: Text(l10n.syncDetailsTitle, style: app.text.label),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: Tokens.space1),
                  child: Row(
                    children: <Widget>[
                      const Flexible(child: SyncStatusPillLive()),
                      const SizedBox(width: Tokens.space2),
                      AppButton(
                        key: const Key('sync-now-setting'),
                        label: l10n.syncNow,
                        variant: AppButtonVariant.tertiary,
                        size: AppButtonSize.medium,
                        expand: false,
                        onPressed: ref.read(syncEngineProvider).syncNow,
                      ),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.syncDetails),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
