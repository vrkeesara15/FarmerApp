import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../orders/commerce_copy.dart';
import '../visits/visit_copy.dart';

/// Farmers captured today (IST), live.
final StreamProvider<int> farmersAddedTodayProvider = StreamProvider<int>((
  ref,
) {
  final (from, to) = istDayBounds(ref.watch(clockProvider)());
  return ref.watch(dutyRepositoryProvider).watchFarmersAdded(from, to);
});

/// A10 Home: DutyToggle at the top (FA-010), today's stats, "Next up",
/// quick actions, SyncStatusPill and the bottom nav.
class HomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  String _noticeText(CoreLocalizations l10n, DutyNotice notice) =>
      switch (notice) {
        DutyNotice.autoEnded => l10n.dutyAutoEndedBody(
          formatTimeIst(DateTime.now().toUtc()),
        ),
        DutyNotice.endedByServer => l10n.dutyServerEndedBody,
        DutyNotice.alreadyActiveElsewhere => l10n.dutyNoticeAlreadyActive,
        DutyNotice.policyNotAccepted => l10n.dutyNoticePolicy,
        DutyNotice.locationUnavailable => l10n.dutyNoticeLocationUnavailable,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final duty = ref.watch(dutyControllerProvider);
    final policy = ref.watch(locationPolicyProvider);
    final controller = ref.read(dutyControllerProvider.notifier);
    final farmersToday = ref.watch(farmersAddedTodayProvider).value ?? 0;
    final verifiedToday = ref.watch(verifiedVisitsTodayProvider).value ?? 0;
    final collectedToday =
        ref
            .watch(collectionsProvider(CollectionsRange.today))
            .value
            ?.collectedPaise ??
        0;
    final blocked = policy.loaded && !policy.accepted;
    final autoEnd = controller.autoEndAt;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: <Widget>[
          SyncStatusPillLive(onTap: () => context.push(AppRoutes.syncDetails)),
          const SizedBox(width: Tokens.space3),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  if (duty.notice != null)
                    _Banner(
                      key: const Key('duty-notice'),
                      icon: Icons.info_outline,
                      color: p.statusInfo,
                      container: p.statusInfoContainer,
                      text: _noticeText(l10n, duty.notice!),
                      onClose: controller.dismissNotice,
                    ),
                  if (duty.integrity.hasIssues)
                    _Banner(
                      key: const Key('integrity-banner'),
                      icon: Icons.shield_outlined,
                      color: p.statusWarning,
                      container: p.statusWarningContainer,
                      text: l10n.integrityBanner,
                    ),
                  DutyToggle(
                    onDuty: duty.onDuty,
                    elapsed: duty.elapsed,
                    loading: duty.busy || !policy.loaded,
                    blockedReason: blocked ? l10n.dutyBlockedPolicy : null,
                    blockedActionLabel: blocked ? l10n.dutyReviewPolicy : null,
                    onBlockedAction: blocked
                        ? () => context.push(AppRoutes.policy)
                        : null,
                    onChanged: (on) =>
                        on ? controller.goOnDuty() : controller.goOffDuty(),
                  ),
                  if (duty.onDuty) ...<Widget>[
                    const SizedBox(height: Tokens.space2),
                    Wrap(
                      spacing: Tokens.space3,
                      runSpacing: Tokens.space1,
                      children: <Widget>[
                        Text(
                          l10n.dutyPointsPending(duty.pointsPending),
                          key: const Key('duty-points-pending'),
                          style: app.text.caption.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        if (autoEnd != null)
                          Text(
                            l10n.dutyAutoEndAt(formatTimeIst(autoEnd)),
                            style: app.text.caption.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Tokens.space2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: const Key('home-my-day'),
                      label: l10n.myDayTitle,
                      icon: Icons.timeline_outlined,
                      variant: AppButtonVariant.tertiary,
                      size: AppButtonSize.medium,
                      expand: false,
                      onPressed: () => context.push(AppRoutes.myDay),
                    ),
                  ),
                  const SizedBox(height: Tokens.space4),
                  Text(l10n.homeTodayStats, style: app.text.heading),
                  const SizedBox(height: Tokens.space2),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: StatTile(
                          value: formatIndianDigits(verifiedToday),
                          label: l10n.statVisitsVerified,
                          icon: Icons.verified_outlined,
                        ),
                      ),
                      const SizedBox(width: Tokens.space2),
                      Expanded(
                        child: StatTile(
                          value: formatIndianDigits(farmersToday),
                          label: l10n.statFarmersAdded,
                          icon: Icons.person_add_alt_1_outlined,
                        ),
                      ),
                      const SizedBox(width: Tokens.space2),
                      Expanded(
                        child: StatTile(
                          key: const Key('home-collections'),
                          value: formatInr(collectedToday, showPaise: false),
                          label: l10n.statCollections,
                          icon: Icons.payments_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Tokens.space4),
                  Text(l10n.homeNextUp, style: app.text.heading),
                  Material(
                    color: p.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Tokens.radiusCard),
                      side: app.borderSide,
                    ),
                    child: EmptyState(
                      icon: Icons.map_outlined,
                      title: l10n.homeNextUpEmpty,
                      help: l10n.homeNextUpEmptyHelp,
                    ),
                  ),
                  const SizedBox(height: Tokens.space4),
                  Text(l10n.homeQuickActions, style: app.text.heading),
                  const SizedBox(height: Tokens.space2),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: Tokens.space2,
                    crossAxisSpacing: Tokens.space2,
                    childAspectRatio: 2.6,
                    children: <Widget>[
                      AppButton(
                        key: const Key('home-add-farmer'),
                        label: l10n.farmersAddFarmer,
                        icon: Icons.person_add_alt_1_outlined,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.medium,
                        onPressed: () => context.push(AppRoutes.addFarmer),
                      ),
                      AppButton(
                        key: const Key('home-start-visit'),
                        label: l10n.actionStartVisit,
                        icon: Icons.place_outlined,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.medium,
                        onPressed: () => context.push(VisitRoutes.start()),
                      ),
                      AppButton(
                        key: const Key('home-scout'),
                        label: l10n.actionScoutCrop,
                        icon: Icons.eco_outlined,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.medium,
                        onPressed: () => context.push(
                          CommerceRoutes.pickFarmer(PickPurpose.scout),
                        ),
                      ),
                      AppButton(
                        key: const Key('home-collect-payment'),
                        label: l10n.actionCollectPayment,
                        icon: Icons.currency_rupee,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.medium,
                        onPressed: () => context.push(
                          CommerceRoutes.pickFarmer(PickPurpose.collect),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (i) {
          switch (i) {
            case 1:
              context.go(AppRoutes.farmers);
            case 2:
              context.go(AppRoutes.visits);
            case 4:
              context.go(AppRoutes.settings);
            case 3:
              context.go(CommerceRoutes.orders);
            default:
              break;
          }
        },
        destinations: <Widget>[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            label: l10n.navFarmers,
          ),
          NavigationDestination(
            icon: const Icon(Icons.place_outlined),
            label: l10n.navVisits,
          ),
          NavigationDestination(
            icon: const Icon(Icons.shopping_bag_outlined),
            label: l10n.navOrders,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: l10n.navMe,
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.container,
    required this.text,
    this.onClose,
    super.key,
  });

  final IconData icon;
  final Color color;
  final Color container;
  final String text;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Tokens.space3,
          Tokens.space2,
          Tokens.space1,
          Tokens.space2,
        ),
        decoration: BoxDecoration(
          color: app.tint(container),
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          border: Border.all(color: color, width: app.borderWidth),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: Tokens.space2),
            Expanded(child: Text(text, style: app.text.body)),
            if (onClose != null)
              IconButton(
                key: const Key('banner-close'),
                icon: const Icon(Icons.close),
                tooltip: CoreLocalizations.of(context).actionClose,
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}
