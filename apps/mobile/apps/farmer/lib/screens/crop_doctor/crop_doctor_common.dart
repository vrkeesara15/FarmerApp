import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';
import '../orders/shop_state.dart' show kisanStoreIdProvider;

/// Pictogram of a crop code (F23 tiles, F20 list).
IconData cropIcon(String? code) => switch (code) {
  'paddy' => Icons.grass,
  'cotton' => Icons.cloud_outlined,
  'chilli' => Icons.local_fire_department_outlined,
  'maize' => Icons.agriculture_outlined,
  'tomato' => Icons.circle_outlined,
  'groundnut' => Icons.spa_outlined,
  'unknown' => Icons.help_outline,
  _ => Icons.eco_outlined,
};

/// The crops the farmer can pick on F23: the crops of their own plots
/// first (with the plot, so the result is attached to it), then the pilot
/// crops.
List<(CropChoice, String)> cropChoices(
  BuildContext context,
  FarmerProfile? profile,
  List<CropRef> crops,
) {
  final lang = Localizations.localeOf(context).languageCode;
  final byId = <String, CropRef>{for (final c in crops) c.id: c};
  final byCode = <String, CropRef>{for (final c in crops) c.code: c};
  final out = <(CropChoice, String)>[];
  final seen = <String>{};
  for (final farm in profile?.farms ?? const <KisanFarm>[]) {
    for (final plot in farm.plots) {
      final ref =
          byId[plot.cropId] ??
          CropRef.pilotFallback.where((c) => c.id == plot.cropId).firstOrNull;
      final code = ref?.code ?? plot.cropId;
      if (!seen.add(code)) continue;
      out.add((
        CropChoice(
          code: code,
          cropId: plot.cropId,
          cropPlotId: plot.id,
          stage: plot.stage,
        ),
        ref?.nameIn(lang) ?? code,
      ));
    }
  }
  for (final c in CropRef.pilotFallback) {
    if (!seen.add(c.code)) continue;
    final real = byCode[c.code] ?? c;
    out.add((CropChoice(code: c.code, cropId: real.id), real.nameIn(lang)));
  }
  return out;
}

/// Name of a crop code in the app language.
String cropCodeName(BuildContext context, List<CropRef> crops, String code) {
  final lang = Localizations.localeOf(context).languageCode;
  final ref =
      crops.where((c) => c.code == code).firstOrNull ??
      CropRef.pilotFallback.where((c) => c.code == code).firstOrNull;
  return ref?.nameIn(lang) ?? code;
}

/// "FCC Kondapur, 3 km" for the store a diagnosis priced its products at
/// (distance from the farmer's cached nearest-store answer).
final FutureProviderFamily<String?, String> diagnosisStoreLabelProvider =
    FutureProvider.family<String?, String>((ref, storeId) async {
      final farmerId = await ref.watch(kisanFarmerIdProvider.future);
      final cache = ref.watch(catalogCacheProvider);
      final nearest = farmerId == null
          ? null
          : await cache.nearestStore(farmerId);
      if (nearest == null || nearest.store.id != storeId) return null;
      return nearest.distanceM == null ? null : formatKm(nearest.distanceM!);
    });

/// FM-006 "Call my officer": one tap to the dialler; without a number the
/// F62 card explains.
Future<void> callMyOfficer(BuildContext context, WidgetRef ref) async {
  final l10n = CoreLocalizations.of(context);
  final phone = ref.read(kisanProfileProvider).value?.value.officer?.phone;
  if (phone == null) {
    unawaited(context.push(AppRoutes.officer));
    return;
  }
  final ok = await ref.read(urlOpenerProvider).open(telUri(phone));
  if (!ok && context.mounted) showKisanMessage(context, l10n.kisanCouldNotOpen);
}

/// FM-006 "Order": the recommended SKU with its label claim goes into the
/// farmer's cart at the diagnosis' store; F31 cart → F32 pay places it.
Future<void> orderFromDiagnosis(
  BuildContext context,
  WidgetRef ref,
  Diagnosis d,
  ProductOption option,
) async {
  if (!d.showBuy) return; // SPEC 3.4: never from a provisional result.
  final farmerId = await ref.read(kisanFarmerIdProvider.future);
  final storeId = d.store?.id ?? await ref.read(kisanStoreIdProvider.future);
  if (farmerId == null) return;
  final item = await catalogItemForOption(
    ref.read(catalogCacheProvider),
    option,
    storeId: storeId,
  );
  ref.read(cartProvider.notifier)
    ..start(farmerId, storeId: storeId)
    ..addRecommended(item, labelClaimId: option.labelClaimId);
  if (context.mounted) unawaited(context.push(AppRoutes.cart));
}

/// Speaks a retake tip (NF-009) when a photo is rejected.
Future<void> speakTip(BuildContext context, WidgetRef ref, String tipKey) {
  final l10n = CoreLocalizations.of(context);
  return ref
      .read(audioPromptProvider)
      .play(
        promptId: tipKey.replaceAll('.', '_'),
        text: l10n.photoTip(tipKey),
        locale: Localizations.localeOf(context),
      )
      .then((_) {}, onError: (Object _) {});
}
