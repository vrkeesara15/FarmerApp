import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/farm_edit.dart';
import '../widgets/kisan_widgets.dart';

/// F40 My crops and farms (FM-003): every farm with its map thumbnail,
/// crops and stages; stage, irrigation and soil change with icon tiles.
/// Cached for offline viewing with "as of".
class MyCropsScreen extends ConsumerWidget {
  /// Creates the screen.
  const MyCropsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final profile = ref.watch(kisanProfileProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanMyCrops)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: profile.when(
                loading: () => const Center(child: CircularProgressIndicator()),
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
                    onRefresh: () =>
                        ref.read(kisanRepositoryProvider).refreshProfile(),
                    child: ListView(
                      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
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
                            child: FarmSummaryCard(farm: farm, editable: true),
                          ),
                        AsOfLabel(cached.asOf),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
