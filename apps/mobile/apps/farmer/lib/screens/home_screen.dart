import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/advisory_widgets.dart';
import '../widgets/kisan_widgets.dart';

/// Refreshes everything the farmer app caches (pull to refresh, start):
/// profile, orders, khata, deletion ticket, and sends queued writes.
Future<void> refreshKisan(WidgetRef ref) async {
  final repo = ref.read(kisanRepositoryProvider);
  final advisory = ref.read(advisoryRepositoryProvider);
  final farmerId = await repo.farmerId();
  await Future.wait(<Future<Object?>>[
    repo.refreshProfile(),
    repo.refreshOrders(),
    repo.refreshDeletion(),
    advisory.refreshCalendar(),
    advisory.refreshAlerts(),
    advisory.refreshInbox(),
    if (farmerId != null) ref.read(khataRepositoryProvider).refresh(farmerId),
    ref.read(kisanFlushProvider)().catchError((Object _) {}),
  ]);
  // The forecast needs a farm, so it is fetched after the profile landed.
  final farms = (await repo.watchProfile().first)?.value.farms;
  if (farms != null && farms.isNotEmpty) {
    await advisory.refreshWeather(farms.first.id);
  }
}

/// F10 Home: greeting, pending visit question, weather strip (FM-008 P1:
/// empty state), a very large "Check my crop" button, dues card when the
/// khata balance is above zero, alerts banner (FM-009 P1: placeholder), my
/// crops with stage and next task, bottom navigation.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(refreshKisan(ref));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final profile = ref.watch(kisanProfileProvider).value;
    final farmerId = ref.watch(kisanFarmerIdProvider).value;
    final khata = farmerId == null
        ? null
        : ref.watch(khataProvider(farmerId)).value;
    final prompts =
        ref.watch(visitPromptsProvider).value ?? const <VisitPrompt>[];
    final crops = ref.watch(cropsProvider).value ?? const <CropRef>[];
    final updated = (ref.watch(diagnosesProvider).value ?? const <Diagnosis>[])
        .where((d) => d.updateUnseen)
        .toList();
    final lang = Localizations.localeOf(context).languageCode;
    final name = profile?.value.firstName ?? '';
    final calendar = ref.watch(cropCalendarProvider).value?.value;
    final farms = profile?.value.farms ?? const <KisanFarm>[];
    return KisanTabScaffold(
      tab: KisanTab.home,
      // FA-008: the tenant's app name and logo, else the working name.
      title: ref.watch(appBrandProvider).name(l10n),
      showBrandLogo: true,
      actions: const <Widget>[_InboxAction()],
      body: RefreshIndicator(
        onRefresh: () => refreshKisan(ref),
        child: ListView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          children: <Widget>[
            Text(
              name.isEmpty
                  ? l10n.kisanGreetingNoName
                  : l10n.kisanGreeting(name),
              key: const Key('home-greeting'),
              style: app.text.title,
            ),
            const SizedBox(height: Tokens.space3),
            for (final prompt in prompts.take(1))
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.space3),
                child: KisanCard(
                  key: const Key('home-visit-prompt'),
                  icon: Icons.how_to_reg_outlined,
                  title: prompt.officerFirstName == null
                      ? l10n.kisanVisitQuestionNoName
                      : l10n.kisanVisitQuestion(prompt.officerFirstName!),
                  onTap: () => context.push(AppRoutes.visit(prompt.visitId)),
                  child: Text(l10n.kisanVisitTapToAnswer, style: app.text.body),
                ),
              ),
            // F27: the agronomist confirmed or corrected a crop check.
            for (final d in updated.take(1))
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.space3),
                child: KisanCard(
                  key: const Key('home-diagnosis-updated'),
                  icon: Icons.notifications_active_outlined,
                  title: l10n.cropDoctorUpdatedTitle,
                  onTap: () => context.push(AppRoutes.cropResult(d.id)),
                  child: Text(
                    l10n.cropDoctorResultUpdatedHome(
                      d.problem?.nameIn(lang) ?? l10n.cropDoctorTitle,
                    ),
                    style: app.text.body,
                  ),
                ),
              ),
            _WeatherStrip(farmId: farms.isEmpty ? null : farms.first.id),
            const SizedBox(height: Tokens.space3),
            SizedBox(
              height: 112,
              child: FilledButton.icon(
                key: const Key('home-check-crop'),
                style: FilledButton.styleFrom(
                  backgroundColor: p.primary,
                  foregroundColor: p.primaryOn,
                  textStyle: app.text.title,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusCard),
                  ),
                ),
                onPressed: () => context.go(AppRoutes.cropDoctor),
                icon: const Icon(Icons.camera_alt, size: 48),
                label: Text(l10n.kisanCheckMyCrop),
              ),
            ),
            const SizedBox(height: Tokens.space3),
            if (khata != null && khata.balancePaise > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.space3),
                child: KisanCard(
                  key: const Key('home-dues'),
                  icon: Icons.account_balance_wallet_outlined,
                  title: l10n.kisanDuesTitle(formatInr(khata.balancePaise)),
                  onTap: () => context.push(AppRoutes.khata),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (khata.nextDueDate != null)
                        Text(
                          l10n.khataDueDate(formatDateIst(khata.nextDueDate!)),
                          style: app.text.body,
                        ),
                      const SizedBox(height: Tokens.space2),
                      AppButton(
                        label: l10n.khataPayNow,
                        icon: Icons.payments_outlined,
                        size: AppButtonSize.medium,
                        onPressed: () => context.push(AppRoutes.khata),
                      ),
                    ],
                  ),
                ),
              ),
            _AlertsBanner(),
            const SizedBox(height: Tokens.space3),
            Text(l10n.kisanMyCrops, style: app.text.heading),
            const SizedBox(height: Tokens.space2),
            if (profile == null || profile.value.plots.isEmpty)
              KisanCard(
                onTap: () => context.push(AppRoutes.crops),
                child: Text(l10n.kisanNoCropsYet, style: app.text.body),
              ),
            if (profile != null)
              for (final plot in profile.value.plots)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.space2),
                  child: KisanCard(
                    key: Key('home-crop-${plot.id}'),
                    icon: stageIcon(plot.stage),
                    title: cropName(context, crops, plot.cropId),
                    onTap: () => context.push(AppRoutes.calendar(plot.id)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          plot.stage == null
                              ? l10n.kisanStageUnknown
                              : l10n.kisanStageIs(
                                  CropStages.label(l10n, plot.stage!),
                                ),
                          style: app.text.body,
                        ),
                        Builder(
                          builder: (context) {
                            final plotCalendar = calendar?.plot(plot.id);
                            final next = plotCalendar?.nextTask(
                              calendar!.today,
                            );
                            return Text(
                              plotCalendar == null
                                  ? l10n.kisanNextTaskSoon
                                  : next == null
                                  ? l10n.calendarAllDone
                                  : l10n.calendarNextTask(
                                      next.titleIn(lang) ?? next.taskKey,
                                    ),
                              key: Key('home-next-${plot.id}'),
                              style: app.text.caption.copyWith(
                                color: p.textSecondary,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            if (profile != null) AsOfLabel(profile.asOf),
            const SizedBox(height: Tokens.space3),
            Wrap(
              spacing: Tokens.space2,
              runSpacing: Tokens.space2,
              children: <Widget>[
                ActionChip(
                  avatar: const Icon(Icons.badge_outlined),
                  label: Text(l10n.kisanMyOfficer),
                  onPressed: () => context.push(AppRoutes.officer),
                ),
                ActionChip(
                  avatar: const Icon(Icons.menu_book_outlined),
                  label: Text(l10n.khataTitle),
                  onPressed: () => context.push(AppRoutes.khata),
                ),
                ActionChip(
                  avatar: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.kisanScanVisitQr),
                  onPressed: () => context.push(AppRoutes.visitScan),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// FM-008 strip: today's sky, temperature and rain chance; tapping opens
/// F43. Falls back to the "coming soon" line while nothing is cached.
class _WeatherStrip extends ConsumerWidget {
  const _WeatherStrip({required this.farmId});

  final String? farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final weather = farmId == null
        ? null
        : ref.watch(farmWeatherProvider(farmId!)).value?.value;
    final today = (weather?.daily.isNotEmpty ?? false)
        ? weather!.daily.first
        : null;
    return Material(
      color: app.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: app.borderSide,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('home-weather'),
        onTap: () => context.push(AppRoutes.weather),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space3),
          child: Row(
            children: <Widget>[
              Icon(
                today == null
                    ? Icons.wb_cloudy_outlined
                    : weatherIcon(today.weatherCode),
                color: today == null
                    ? app.palette.textSecondary
                    : app.palette.primary,
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Text(
                  today == null
                      ? l10n.kisanWeatherSoon
                      : '${weatherSky(l10n, today.weatherCode)} \u00b7 '
                            '${l10n.weatherTempRange(today.temperatureMinC.round().toString(), today.temperatureMaxC.round().toString())}',
                  style: app.text.body.copyWith(
                    color: today == null ? app.palette.textSecondary : null,
                  ),
                ),
              ),
              if (today != null)
                Text(
                  l10n.weatherRainChance(today.precipitationProbabilityPct),
                  style: app.text.caption.copyWith(
                    color: app.palette.textSecondary,
                  ),
                ),
              Icon(Icons.chevron_right, color: app.palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// FM-009 banner: the most severe district alert; tapping opens F44.
class _AlertsBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final alerts =
        ref.watch(outbreakAlertsProvider).value?.value ??
        const <OutbreakAlert>[];
    final top = alerts.isEmpty ? null : alerts.first;
    return Material(
      color: app.tint(app.palette.primaryContainer),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: app.borderSide,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('home-alerts'),
        onTap: () => context.push(AppRoutes.alerts),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space3),
          child: Row(
            children: <Widget>[
              Icon(
                top == null
                    ? Icons.notifications_none
                    : Icons.warning_amber_outlined,
                color: top == null
                    ? app.palette.primary
                    : app.palette.statusWarning,
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Text(
                  top == null
                      ? l10n.kisanNoAlerts
                      : '${top.problemNameIn(lang) ?? top.problemCode ?? ''} \u00b7 '
                            '${top.cropNameIn(lang) ?? top.cropCode}',
                  style: app.text.body,
                ),
              ),
              if (top != null) SeverityChip(top.severity),
            ],
          ),
        ),
      ),
    );
  }
}

/// FA-007 inbox action with the unread badge.
class _InboxAction extends ConsumerWidget {
  const _InboxAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final unread = ref.watch(inboxUnreadProvider).value ?? 0;
    return IconButton(
      key: const Key('home-inbox'),
      onPressed: () => context.push(AppRoutes.inbox),
      tooltip: l10n.farmerInboxTitle,
      icon: Badge.count(
        key: const Key('home-inbox-badge'),
        count: unread,
        isLabelVisible: unread > 0,
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}
