import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/kisan_widgets.dart';

/// Refreshes everything the farmer app caches (pull to refresh, start):
/// profile, orders, khata, deletion ticket, and sends queued writes.
Future<void> refreshKisan(WidgetRef ref) async {
  final repo = ref.read(kisanRepositoryProvider);
  final farmerId = await repo.farmerId();
  await Future.wait(<Future<Object?>>[
    repo.refreshProfile(),
    repo.refreshOrders(),
    repo.refreshDeletion(),
    if (farmerId != null) ref.read(khataRepositoryProvider).refresh(farmerId),
    ref.read(kisanFlushProvider)().catchError((Object _) {}),
  ]);
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
    final name = profile?.value.firstName ?? '';
    return KisanTabScaffold(
      tab: KisanTab.home,
      title: l10n.appNameFarmer,
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
            _WeatherStrip(),
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
                    onTap: () => context.push(AppRoutes.crops),
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
                        Text(
                          l10n.kisanNextTaskSoon,
                          style: app.text.caption.copyWith(
                            color: p.textSecondary,
                          ),
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

class _WeatherStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return Container(
      key: const Key('home-weather'),
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: app.palette.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.wb_cloudy_outlined, color: app.palette.textSecondary),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Text(
              l10n.kisanWeatherSoon,
              style: app.text.body.copyWith(color: app.palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return Container(
      key: const Key('home-alerts'),
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: app.tint(app.palette.primaryContainer),
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.notifications_none, color: app.palette.primary),
          const SizedBox(width: Tokens.space2),
          Expanded(child: Text(l10n.kisanNoAlerts, style: app.text.body)),
        ],
      ),
    );
  }
}
