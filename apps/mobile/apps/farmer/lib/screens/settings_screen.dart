import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main_version.dart';
import '../router.dart';
import '../widgets/kisan_widgets.dart';
import 'officer_screen.dart' show telUri;

/// F70 notifications preference, live.
final FutureProvider<bool> kisanNotificationsProvider = FutureProvider<bool>(
  (ref) => ref.watch(kisanRepositoryProvider).notificationsOn(),
);

/// F70 Me: language, theme (Light / Sunlight), notifications, consent
/// settings (withdraw offers), my crops and field officer, help (call the
/// store), delete my account (FM-015), about.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  Future<void> _playLanguage(WidgetRef ref, Locale locale) async {
    await ref
        .read(audioPromptProvider)
        .play(
          promptId: 'f01_language',
          text: lookupCoreLocalizations(locale).kisanLanguagePrompt,
          locale: locale,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final sunlight = settings.themeMode == AppThemeMode.sunlight;
    final notifications = ref.watch(kisanNotificationsProvider).value ?? true;
    final consents = ref.watch(kisanConsentsProvider).value;
    final deletion = ref.watch(kisanDeletionProvider).value;
    final support = ref
        .watch(tenantSettingsProvider)
        .value
        ?.branding
        .supportPhone;

    Widget tile({
      required Key key,
      required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: app.borderSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: key,
          minTileHeight: Tokens.sizePrimaryButtonHeight,
          leading: Icon(icon, color: color ?? p.primary),
          title: Text(title, style: app.text.label.copyWith(color: color)),
          subtitle: subtitle == null
              ? null
              : Text(subtitle, style: app.text.body),
          trailing: onTap == null
              ? null
              : Icon(Icons.chevron_right, color: p.textSecondary),
          onTap: onTap,
        ),
      ),
    );

    return KisanTabScaffold(
      tab: KisanTab.me,
      title: l10n.settingsTitle,
      body: RefreshOnOpen(
        onOpen: (ref) async {
          final repo = ref.read(kisanRepositoryProvider);
          await repo.refreshProfile();
          await repo.refreshDeletion();
        },
        child: ListView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          children: <Widget>[
            LanguageSettingTile(
              value: settings.locale,
              onChanged: notifier.setLocale,
              onPlayAudio: (locale) => _playLanguage(ref, locale),
            ),
            const SizedBox(height: Tokens.space2),
            Material(
              color: p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusCard),
                side: app.borderSide,
              ),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                key: const Key('theme-setting'),
                secondary: Icon(
                  sunlight ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                  color: p.primary,
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
            const SizedBox(height: Tokens.space2),
            Material(
              color: p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusCard),
                side: app.borderSide,
              ),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                key: const Key('notifications-setting'),
                secondary: Icon(
                  notifications
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: p.primary,
                ),
                title: Text(l10n.kisanNotifications, style: app.text.label),
                subtitle: Text(
                  notifications ? l10n.kisanOn : l10n.kisanOff,
                  style: app.text.body,
                ),
                value: notifications,
                onChanged: (on) async {
                  await ref.read(kisanRepositoryProvider).setNotifications(on);
                  ref.invalidate(kisanNotificationsProvider);
                },
              ),
            ),
            const SizedBox(height: Tokens.space2),
            tile(
              key: const Key('me-consent'),
              icon: Icons.privacy_tip_outlined,
              title: l10n.kisanConsentSettings,
              subtitle: consents == null
                  ? null
                  : consents.marketingGranted
                  ? l10n.kisanOffersOn
                  : l10n.kisanOffersOff,
              onTap: () => context.push(AppRoutes.consentSettings),
            ),
            tile(
              key: const Key('me-crops'),
              icon: Icons.grass,
              title: l10n.kisanMyCrops,
              onTap: () => context.push(AppRoutes.crops),
            ),
            tile(
              key: const Key('me-officer'),
              icon: Icons.badge_outlined,
              title: l10n.kisanMyOfficer,
              onTap: () => context.push(AppRoutes.officer),
            ),
            tile(
              key: const Key('me-referral'),
              icon: Icons.card_giftcard_outlined,
              title: l10n.referralOpen,
              onTap: () => context.push(AppRoutes.referral),
            ),
            tile(
              key: const Key('me-help'),
              icon: Icons.support_agent,
              title: l10n.kisanHelpCallStore,
              subtitle: support ?? l10n.kisanHelpNoPhone,
              onTap: support == null
                  ? null
                  : () async {
                      final ok = await ref
                          .read(urlOpenerProvider)
                          .open(telUri(support));
                      if (!ok && context.mounted) {
                        showKisanMessage(context, l10n.kisanCouldNotOpen);
                      }
                    },
            ),
            tile(
              key: const Key('me-delete'),
              icon: Icons.delete_outline,
              title: l10n.kisanDeleteAccount,
              subtitle: deletion == null
                  ? null
                  : l10n.kisanDeleteRequested(deletion.shortTicket),
              color: p.statusDanger,
              onTap: () => context.push(AppRoutes.deleteAccount),
            ),
            tile(
              key: const Key('me-about'),
              icon: Icons.info_outline,
              title: l10n.kisanAbout,
              subtitle: l10n.kisanAboutVersion(
                l10n.appNameFarmer,
                kisanAppVersion,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
