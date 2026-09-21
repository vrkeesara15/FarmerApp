import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../session.dart';

/// A63 Profile and settings: language, theme (Light/Sunlight) and the sync
/// row (status pill, "Sync now", opens A64 Sync details).
///
/// It is also the "Me" hub: A13 inbox, A60 performance, A61 travel
/// allowance and A62 my flags hang off it, plus A35 meetings and A36 demo
/// plots.
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
    final support = ref.watch(supportPhoneProvider);
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
            // Store mode switch (SPEC 1.2): store managers, accountants and
            // cluster heads (read-only); field officers never see it.
            if (ref.watch(storeRoleProvider).hasStoreMode) ...<Widget>[
              const SizedBox(height: Tokens.space3),
              Material(
                color: app.palette.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusCard),
                  side: app.borderSide,
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: const Key('store-mode-setting'),
                  leading: Icon(
                    Icons.storefront_outlined,
                    color: app.palette.primary,
                  ),
                  title: Text(l10n.storeModeTitle, style: app.text.label),
                  subtitle: Text(
                    l10n.storeSettingsEntryHint,
                    style: app.text.body,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.store),
                ),
              ),
            ],
            const SizedBox(height: Tokens.space4),
            Text(l10n.meSectionTitle, style: app.text.heading),
            const SizedBox(height: Tokens.space2),
            _MeTile(
              itemKey: const Key('me-inbox'),
              icon: Icons.notifications_none_outlined,
              title: l10n.inboxTitle,
              badge: ref.watch(unreadCountProvider),
              route: AppRoutes.inbox,
            ),
            _MeTile(
              itemKey: const Key('me-beat'),
              icon: Icons.map_outlined,
              title: l10n.beatTitle,
              route: AppRoutes.beat,
            ),
            _MeTile(
              itemKey: const Key('me-performance'),
              icon: Icons.insights_outlined,
              title: l10n.performanceTitle,
              route: AppRoutes.performance,
            ),
            _MeTile(
              itemKey: const Key('me-travel'),
              icon: Icons.directions_bike_outlined,
              title: l10n.travelTitle,
              route: AppRoutes.travel,
            ),
            _MeTile(
              itemKey: const Key('me-flags'),
              icon: Icons.flag_outlined,
              title: l10n.flagsTitle,
              route: AppRoutes.myFlags,
            ),
            _MeTile(
              itemKey: const Key('me-meetings'),
              icon: Icons.groups_outlined,
              title: l10n.meetingsTitle,
              route: AppRoutes.meetings,
            ),
            _MeTile(
              itemKey: const Key('me-demo-plots'),
              icon: Icons.science_outlined,
              title: l10n.demoTitle,
              route: AppRoutes.demoPlots,
            ),
            const SizedBox(height: Tokens.space3),
            // FA-008: the tenant's own support number, from the branding in
            // `GET /v1/settings/public`. Disabled when the tenant set none.
            Material(
              color: app.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusCard),
                side: app.borderSide,
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: const Key('support-setting'),
                leading: Icon(Icons.support_agent, color: app.palette.primary),
                title: Text(l10n.settingsCallSupport, style: app.text.label),
                subtitle: Text(
                  support ?? l10n.settingsCallSupportNone,
                  style: app.text.body,
                ),
                onTap: support == null
                    ? null
                    : () async {
                        final ok = await ref
                            .read(urlOpenerProvider)
                            .open(telUri(support));
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.settingsCallSupportFailed),
                            ),
                          );
                        }
                      },
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
                key: const Key('logout-setting'),
                leading: Icon(Icons.logout, color: app.palette.statusDanger),
                title: Text(l10n.settingsLogOut, style: app.text.label),
                subtitle: Text(l10n.settingsLogOutHelp, style: app.text.body),
                onTap: () async {
                  await signOutMitra(ref);
                  if (context.mounted) context.go(AppRoutes.phone);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeTile extends ConsumerWidget {
  const _MeTile({
    required this.itemKey,
    required this.icon,
    required this.title,
    required this.route,
    this.badge = 0,
  });

  final Key itemKey;
  final IconData icon;
  final String title;
  final String route;
  final int badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      child: Material(
        color: app.palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: app.borderSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: itemKey,
          leading: Badge(
            isLabelVisible: badge > 0,
            label: Text('$badge'),
            child: Icon(icon, color: app.palette.primary),
          ),
          title: Text(title, style: app.text.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        ),
      ),
    );
  }
}
