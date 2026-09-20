import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/farm_edit.dart';
import '../widgets/kisan_widgets.dart';

/// F40 My crops and farms (FM-003, FM-007): every farm with its map
/// thumbnail, crops, stage and next task from the synced crop calendar;
/// stage, irrigation and soil change with icon tiles, "Add a crop" opens
/// F41, and shortcuts lead to the weather (F43) and the alerts (F44).
/// Cached for offline viewing with "as of".
class MyCropsScreen extends ConsumerWidget {
  /// Creates the screen.
  const MyCropsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final profile = ref.watch(kisanProfileProvider);
    final calendar = ref.watch(cropCalendarProvider).value?.value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanMyCrops)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('crops-add'),
        onPressed: () => context.push(AppRoutes.addCrop),
        icon: const Icon(Icons.add),
        label: Text(l10n.kisanAddCrop),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: RefreshOnOpen(
                onOpen: (ref) =>
                    ref.read(advisoryRepositoryProvider).refreshCalendar(),
                child: profile.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const ErrorState(),
                  data: (cached) {
                    if (cached == null || cached.value.farms.isEmpty) {
                      return EmptyState(
                        icon: Icons.grass,
                        title: l10n.kisanNoCropsYet,
                        help: l10n.kisanNoCropsHelp,
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        await ref
                            .read(kisanRepositoryProvider)
                            .refreshProfile();
                        await ref
                            .read(advisoryRepositoryProvider)
                            .refreshCalendar();
                      },
                      child: ListView(
                        padding: const EdgeInsets.all(
                          Tokens.spaceScreenPadding,
                        ),
                        children: <Widget>[
                          SpokenText(
                            promptId: 'f40_help',
                            text: l10n.kisanWelcomeEditHelp,
                          ),
                          for (final farm in cached.value.farms)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: Tokens.space3,
                              ),
                              child: FarmSummaryCard(
                                farm: farm,
                                editable: true,
                                calendar: calendar,
                                onOpenCalendar: (plotId) =>
                                    context.push(AppRoutes.calendar(plotId)),
                              ),
                            ),
                          Wrap(
                            spacing: Tokens.space2,
                            runSpacing: Tokens.space2,
                            children: <Widget>[
                              ActionChip(
                                key: const Key('crops-weather'),
                                avatar: const Icon(Icons.wb_cloudy_outlined),
                                label: Text(l10n.kisanWeather),
                                onPressed: () =>
                                    context.push(AppRoutes.weather),
                              ),
                              ActionChip(
                                key: const Key('crops-alerts'),
                                avatar: const Icon(
                                  Icons.warning_amber_outlined,
                                ),
                                label: Text(l10n.kisanAlerts),
                                onPressed: () => context.push(AppRoutes.alerts),
                              ),
                            ],
                          ),
                          const SizedBox(height: Tokens.space2),
                          AsOfLabel(cached.asOf),
                          const SizedBox(height: Tokens.space8),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
