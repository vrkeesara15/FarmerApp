import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/advisory_widgets.dart';
import '../../widgets/kisan_widgets.dart';

/// F44 Alerts (FM-009): the district's pest and disease alerts with the
/// derived severity, the crop, what to look for and what to do (F20 crop
/// doctor, F30 store), and "hide this alert". F27 — a crop check the
/// agronomist confirmed or corrected — is surfaced at the top of the same
/// list, because that is the other thing the farmer must act on.
class AlertsScreen extends ConsumerWidget {
  /// Creates the screen.
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final cached = ref.watch(outbreakAlertsProvider).value;
    final updated = (ref.watch(diagnosesProvider).value ?? const <Diagnosis>[])
        .where((d) => d.updateUnseen)
        .toList();
    final alerts = cached?.value ?? const <OutbreakAlert>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.alertsTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: RefreshOnOpen(
                onOpen: (ref) =>
                    ref.read(advisoryRepositoryProvider).refreshAlerts(),
                child: alerts.isEmpty && updated.isEmpty
                    ? EmptyState(
                        icon: Icons.notifications_none,
                        title: l10n.alertsNone,
                        help: l10n.alertsNoneHelp,
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref
                            .read(advisoryRepositoryProvider)
                            .refreshAlerts(),
                        child: ListView(
                          padding: const EdgeInsets.all(
                            Tokens.spaceScreenPadding,
                          ),
                          children: <Widget>[
                            for (final d in updated)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Tokens.space3,
                                ),
                                child: _DiagnosisUpdatedCard(diagnosis: d),
                              ),
                            for (final alert in alerts)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Tokens.space3,
                                ),
                                child: _AlertCard(alert: alert),
                              ),
                            if (cached != null) AsOfLabel(cached.asOf),
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

/// F27 result-updated state, on the alerts list as well as on F10.
class _DiagnosisUpdatedCard extends StatelessWidget {
  const _DiagnosisUpdatedCard({required this.diagnosis});

  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    return KisanCard(
      key: Key('alerts-diagnosis-${diagnosis.id}'),
      icon: Icons.notifications_active_outlined,
      title: l10n.cropDoctorUpdatedTitle,
      onTap: () => context.push(AppRoutes.cropResult(diagnosis.id)),
      child: Text(
        l10n.cropDoctorResultUpdatedHome(
          diagnosis.problem?.nameIn(lang) ?? l10n.cropDoctorTitle,
        ),
        style: app.text.body,
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.alert});

  final OutbreakAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final problem = alert.problemNameIn(lang) ?? alert.problemCode ?? '';
    final crop = alert.cropNameIn(lang) ?? alert.cropCode;
    final spoken =
        '$problem. $crop. ${l10n.alertLookForTitle}. '
        '${alertSymptoms(l10n, alert.problemType).join('. ')}';
    return Card(
      key: Key('alert-${alert.id}'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.warning_amber_outlined,
                  size: Tokens.space6,
                  color: p.statusWarning,
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(problem, style: app.text.heading),
                      Text(
                        '$crop · ${alert.district}',
                        style: app.text.body.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                SeverityChip(alert.severity),
              ],
            ),
            const SizedBox(height: Tokens.space2),
            Wrap(
              spacing: Tokens.space2,
              runSpacing: Tokens.space1,
              children: <Widget>[
                if (alert.growsCrop ?? false)
                  Chip(
                    key: Key('alert-grows-${alert.id}'),
                    avatar: Icon(
                      Icons.grass,
                      size: Tokens.space4 + 2,
                      color: p.primary,
                    ),
                    label: Text(l10n.alertGrowsCrop, style: app.text.label),
                  ),
                Chip(
                  avatar: Icon(
                    Icons.groups_outlined,
                    size: Tokens.space4 + 2,
                    color: p.textSecondary,
                  ),
                  label: Text(
                    l10n.alertFarmersAffected(alert.farmersAffected),
                    style: app.text.label,
                  ),
                ),
                Chip(
                  avatar: Icon(
                    Icons.calendar_today_outlined,
                    size: Tokens.space4 + 2,
                    color: p.textSecondary,
                  ),
                  label: Text(
                    l10n.alertWeekOf(formatDateIst(alert.weekStart)),
                    style: app.text.label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space3),
            Text(l10n.alertLookForTitle, style: app.text.label),
            for (final sign in alertSymptoms(l10n, alert.problemType))
              Padding(
                padding: const EdgeInsets.only(top: Tokens.space1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.check_box_outline_blank,
                      size: Tokens.space4,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: Tokens.space2),
                    Expanded(child: Text(sign, style: app.text.body)),
                  ],
                ),
              ),
            AudioButton(promptId: 'f44_alert', text: spoken),
            const SizedBox(height: Tokens.space2),
            Text(l10n.alertDoTitle, style: app.text.label),
            const SizedBox(height: Tokens.space2),
            AppButton(
              key: Key('alert-check-${alert.id}'),
              label: l10n.alertCheckCrop,
              icon: Icons.camera_alt_outlined,
              onPressed: () => context.go(AppRoutes.cropDoctor),
            ),
            const SizedBox(height: Tokens.space2),
            AppButton(
              key: Key('alert-shop-${alert.id}'),
              label: l10n.alertSeeProducts,
              icon: Icons.storefront_outlined,
              size: AppButtonSize.medium,
              onPressed: () => context.push(AppRoutes.shop),
            ),
            const SizedBox(height: Tokens.space1),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('alert-dismiss-${alert.id}'),
                onPressed: () async {
                  await ref
                      .read(advisoryRepositoryProvider)
                      .dismissAlert(alert.id);
                  if (context.mounted) {
                    showKisanMessage(context, l10n.alertHidden);
                  }
                },
                icon: const Icon(Icons.visibility_off_outlined),
                label: Text(l10n.alertDismiss),
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    Tokens.sizeTouchTargetMin,
                    Tokens.sizeTouchTargetMin,
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
