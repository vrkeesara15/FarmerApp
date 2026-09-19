import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../khata/khata_screen.dart';
import '../orders/commerce_copy.dart';
import '../orders/orders_screen.dart';
import '../scouting/scouting_screens.dart';
import '../visits/visit_copy.dart';
import '../visits/visits_list_screen.dart';
import 'wizard_copy.dart';

/// A22 Farmer profile: Overview (key facts, crop chips, farms with a mini
/// MapPanel), Visits, Diagnoses (FA-019 scouting results), Orders and
/// Khata tabs, primary actions (Start visit, Scout, New order, Collect),
/// sync / duplicate banners.
class FarmerProfileScreen extends ConsumerWidget {
  /// Creates the screen.
  const FarmerProfileScreen({required this.farmerId, super.key});

  /// Farmer id.
  final String farmerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final detail = ref.watch(farmerDetailProvider(farmerId));
    return detail.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          onRetry: () => ref.invalidate(farmerDetailProvider(farmerId)),
        ),
      ),
      data: (d) => d == null
          ? Scaffold(
              appBar: AppBar(title: Text(l10n.profileNotFound)),
              body: EmptyState(
                icon: Icons.person_off_outlined,
                title: l10n.profileNotFound,
              ),
            )
          : _Profile(detail: d),
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.detail});

  final FarmerDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final f = detail.farmer;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(f.name),
          leading: BackButton(
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(AppRoutes.farmers),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: app.text.label,
            tabs: <Widget>[
              Tab(text: l10n.profileTabOverview),
              Tab(text: l10n.profileTabVisits),
              Tab(text: l10n.profileTabDiagnoses),
              Tab(text: l10n.profileTabOrders),
              Tab(text: l10n.profileTabKhata),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(Tokens.space3),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(top: app.borderSide),
            ),
            child: GridView.count(
              key: const Key('profile-actions'),
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Tokens.space2,
              crossAxisSpacing: Tokens.space2,
              childAspectRatio: 3.2,
              children: <Widget>[
                AppButton(
                  key: const Key('profile-start-visit'),
                  label: l10n.profileStartVisit,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  icon: Icons.play_circle_outline,
                  onPressed: () => context.push(
                    VisitRoutes.start(
                      farmerId: f.id,
                      farmId: detail.farms.firstOrNull?.farm.id,
                    ),
                  ),
                ),
                AppButton(
                  key: const Key('profile-scout'),
                  label: l10n.profileScout,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  icon: Icons.search,
                  onPressed: () => context.push(ScoutRoutes.plot(f.id)),
                ),
                AppButton(
                  key: const Key('profile-new-order'),
                  label: l10n.profileNewOrder,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  icon: Icons.add_shopping_cart,
                  onPressed: () => context.push(CommerceRoutes.catalogue(f.id)),
                ),
                AppButton(
                  key: const Key('profile-collect'),
                  label: l10n.profileCollect,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  icon: Icons.currency_rupee,
                  onPressed: () => context.push(CommerceRoutes.collect(f.id)),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              const OfflineBannerLive(),
              if (detail.isDuplicate)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Tokens.spaceScreenPadding,
                    Tokens.space3,
                    Tokens.spaceScreenPadding,
                    0,
                  ),
                  child: NoticeBox(
                    key: const Key('profile-duplicate'),
                    text:
                        '${l10n.profileDuplicateTitle}\n${l10n.profileDuplicateBody}',
                    icon: Icons.merge_type,
                    color: p.statusWarning,
                    container: p.statusWarningContainer,
                    action: detail.duplicateOfId == null
                        ? AppButton(
                            label: l10n.profileRejectedHelp,
                            variant: AppButtonVariant.tertiary,
                            size: AppButtonSize.medium,
                            expand: false,
                            icon: Icons.sync_problem,
                            onPressed: () =>
                                context.push(AppRoutes.syncDetails),
                          )
                        : AppButton(
                            key: const Key('profile-open-duplicate'),
                            label: l10n.regDuplicateOpen,
                            variant: AppButtonVariant.secondary,
                            size: AppButtonSize.medium,
                            icon: Icons.open_in_new,
                            onPressed: () => context.push(
                              AppRoutes.farmerPath(detail.duplicateOfId!),
                            ),
                          ),
                  ),
                )
              else if (detail.rejection != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Tokens.spaceScreenPadding,
                    Tokens.space3,
                    Tokens.spaceScreenPadding,
                    0,
                  ),
                  child: NoticeBox(
                    key: const Key('profile-rejected'),
                    text: '${l10n.profileRejectedTitle}: ${detail.rejection}',
                    icon: Icons.error_outline,
                    color: p.statusDanger,
                    container: p.statusDangerContainer,
                    action: AppButton(
                      label: l10n.profileRejectedHelp,
                      variant: AppButtonVariant.tertiary,
                      size: AppButtonSize.medium,
                      expand: false,
                      icon: Icons.sync_problem,
                      onPressed: () => context.push(AppRoutes.syncDetails),
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _Overview(detail: detail),
                    _Visits(farmerId: f.id),
                    FarmerDiagnosesList(farmerId: f.id),
                    _Orders(farmerId: f.id),
                    KhataBody(farmerId: f.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.detail});

  final FarmerDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final f = detail.farmer;
    final crops = <String, CropRef>{
      for (final c in ref.watch(cropsProvider).value ?? CropRef.pilotFallback)
        c.id: c,
    };
    final cropIds = <String>{
      for (final plot in detail.plots)
        if (plot.cropId != null) plot.cropId!,
    };
    return ListView(
      key: const Key('profile-overview'),
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      children: <Widget>[
        if (detail.pendingSync)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space3),
            child: Row(
              key: const Key('profile-pending-sync'),
              children: <Widget>[
                Icon(Icons.cloud_upload_outlined, color: p.statusInfo),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    l10n.farmerPendingSync,
                    style: app.text.label.copyWith(color: p.statusInfo),
                  ),
                ),
              ],
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space3),
            child: Column(
              children: <Widget>[
                FactRow(
                  label: l10n.profilePhone,
                  value:
                      '${fromE164India(f.phone ?? '')} · '
                      '${f.phoneVerified ? l10n.regPhoneVerified : l10n.farmerPhoneUnverified}',
                  icon: Icons.phone_outlined,
                ),
                FactRow(
                  label: l10n.farmerVillage,
                  value: detail.village?.name ?? '—',
                  icon: Icons.place_outlined,
                ),
                if (f.landmark != null && f.landmark!.isNotEmpty)
                  FactRow(
                    label: l10n.profileLandmark,
                    value: f.landmark!,
                    icon: Icons.flag_outlined,
                  ),
                FactRow(
                  label: l10n.profileLanguage,
                  value:
                      LanguageOption.launchLanguages
                          .where(
                            (o) =>
                                o.locale.languageCode ==
                                (f.preferredLanguage ?? f.language),
                          )
                          .firstOrNull
                          ?.nativeName ??
                      '—',
                  icon: Icons.translate,
                ),
                if (f.landOwnership != null)
                  FactRow(
                    label: l10n.profileOwnership,
                    value: LandOwnershipTypes.label(l10n, f.landOwnership!),
                    icon: Icons.home_outlined,
                  ),
                FactRow(
                  label: l10n.consentDataCardTitle,
                  value:
                      detail.consents.any(
                        (c) => c.purpose == 'data' && c.granted,
                      )
                      ? l10n.consentGiven
                      : l10n.consentNotGiven,
                  icon: Icons.verified_user_outlined,
                ),
                FactRow(
                  label: l10n.consentOffersCardTitle,
                  value: f.consentMarketing
                      ? l10n.consentGiven
                      : l10n.consentNotGiven,
                  icon: Icons.campaign_outlined,
                ),
              ],
            ),
          ),
        ),
        if (!f.phoneVerified)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Tooltip(
                message: l10n.profileComingSoon,
                child: AppButton(
                  key: const Key('profile-verify-phone'),
                  label: l10n.profileVerifyPhone,
                  variant: AppButtonVariant.tertiary,
                  size: AppButtonSize.medium,
                  expand: false,
                  icon: Icons.verified_outlined,
                  onPressed: null,
                ),
              ),
            ),
          ),
        if (cropIds.isNotEmpty) ...<Widget>[
          SectionTitle(l10n.regStepCrops),
          Wrap(
            spacing: Tokens.space2,
            runSpacing: Tokens.space2,
            children: <Widget>[
              for (final id in cropIds)
                CropChip(
                  data: CropChipData(
                    name: cropName(
                      context,
                      crops[id] ?? CropRef(id: id, code: id, name: id),
                    ),
                  ),
                ),
            ],
          ),
        ],
        SectionTitle(
          l10n.profileFarms,
          trailing: AppButton(
            key: const Key('profile-add-farm'),
            label: l10n.profileAddFarm,
            variant: AppButtonVariant.tertiary,
            size: AppButtonSize.medium,
            expand: false,
            icon: Icons.add_location_alt_outlined,
            onPressed: () => context.push(AppRoutes.addFarmPath(f.id)),
          ),
        ),
        if (detail.farms.isEmpty)
          Text(
            l10n.profileNoFarms,
            style: app.text.body.copyWith(color: p.textSecondary),
          ),
        for (final (i, farm) in detail.farms.indexed) ...<Widget>[
          if (i > 0) const SizedBox(height: Tokens.space3),
          Card(
            key: Key('profile-farm-${farm.farm.id}'),
            child: Padding(
              padding: const EdgeInsets.all(Tokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          farm.farm.name ?? l10n.regFarmIndex(i + 1),
                          style: app.text.heading,
                        ),
                      ),
                      AppButton(
                        key: Key('profile-edit-farm-${farm.farm.id}'),
                        label: l10n.profileEditFarm,
                        variant: AppButtonVariant.tertiary,
                        size: AppButtonSize.medium,
                        expand: false,
                        icon: Icons.edit_outlined,
                        onPressed: () => context.push(
                          AppRoutes.editFarmPath(f.id, farm.farm.id),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Tokens.space2),
                  MapPanel(
                    boundary: farm.boundary,
                    interactive: false,
                    height: 140,
                    tileProvider: ref.watch(mapTileProviderProvider),
                  ),
                  const SizedBox(height: Tokens.space2),
                  Text(
                    <String>[
                      if (farm.farm.areaAcres != null)
                        l10n.profileAcres(acresText(farm.farm.areaAcres!)),
                      l10n.profileFarmPlots(farm.plots.length),
                      if (farm.farm.soil != null)
                        SoilTypes.label(l10n, farm.farm.soil!),
                      if (farm.farm.irrigation != null)
                        IrrigationTypes.label(l10n, farm.farm.irrigation!),
                    ].join(' · '),
                    style: app.text.body.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: Tokens.space2),
                  Wrap(
                    spacing: Tokens.space2,
                    runSpacing: Tokens.space2,
                    children: <Widget>[
                      for (final plot in farm.plots)
                        CropChip(
                          data: CropChipData(
                            name: plot.cropId == null
                                ? '—'
                                : cropName(
                                    context,
                                    crops[plot.cropId] ??
                                        CropRef(
                                          id: plot.cropId!,
                                          code: plot.cropId!,
                                          name: plot.cropId!,
                                        ),
                                  ),
                            stage: plot.season == null
                                ? null
                                : Seasons.label(l10n, plot.season!),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: Tokens.space6),
      ],
    );
  }
}

class _Visits extends ConsumerWidget {
  const _Visits({required this.farmerId});

  final String farmerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final rows =
        ref.watch(farmerVisitsProvider(farmerId)).value ??
        const <VisitSummary>[];
    if (rows.isEmpty) {
      return Center(
        child: EmptyState(
          key: const Key('profile-visits-empty'),
          icon: Icons.event_outlined,
          title: l10n.profileVisitsEmpty,
          help: l10n.visitsEmptyHelp,
        ),
      );
    }
    return ListView.separated(
      key: const Key('profile-visits'),
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: Tokens.space2),
      itemBuilder: (context, i) => VisitSummaryCard(summary: rows[i]),
    );
  }
}

class _Orders extends ConsumerWidget {
  const _Orders({required this.farmerId});

  final String farmerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final rows =
        ref.watch(farmerOrdersProvider(farmerId)).value ?? const <OrderView>[];
    if (rows.isEmpty) {
      return Center(
        child: EmptyState(
          key: const Key('profile-orders-empty'),
          icon: Icons.shopping_bag_outlined,
          title: l10n.profileOrdersEmpty,
          actionLabel: l10n.profileNewOrder,
          onAction: () => context.push(CommerceRoutes.catalogue(farmerId)),
        ),
      );
    }
    return ListView.separated(
      key: const Key('profile-orders'),
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: Tokens.space2),
      itemBuilder: (context, i) =>
          OrderSummaryTile(view: rows[i], showFarmer: false),
    );
  }
}
