import 'package:flutter/material.dart';

import '../diagnosis/diagnosis_models.dart';
import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'app_button.dart';
import 'confidence_band.dart';
import 'diagnosis_result_card.dart';
import 'product_card.dart';
import 'treatment_card.dart';

/// Stable keys of the result screens (tests assert the SPEC 3.4 rule on
/// them in both apps).
abstract final class DiagnosisKeys {
  /// The primary buy / order action of the action bar.
  static const Key buy = Key('diagnosis-buy');

  /// "Talk to your field officer" / "Call my officer".
  static const Key talkToOfficer = Key('diagnosis-talk-officer');

  /// "Ask an expert".
  static const Key askExpert = Key('diagnosis-ask-expert');

  /// F27 updated banner.
  static const Key updatedBanner = Key('diagnosis-updated-banner');

  /// F28 out-of-scope card.
  static const Key outOfScope = Key('diagnosis-out-of-scope');

  /// "Products at FCC Kondapur, 3 km".
  static const Key store = Key('diagnosis-store');

  /// Order button of one product card.
  static Key orderProduct(String skuId) => Key('diagnosis-order-$skuId');

  /// Treatment card of one option.
  static Key treatment(String skuId) => Key('diagnosis-treatment-$skuId');
}

/// Headline for the diagnosis' `message_key` (FM-005, DX-010).
String diagnosisHeadline(CoreLocalizations l10n, Diagnosis d) {
  if (d.isOutOfScope) return diagnosisOutOfScopeTitle(l10n, d.outOfScopeReason);
  return switch (d.messageKey) {
    'diagnosis.result.answered' => l10n.cropDoctorMessageAnswered,
    'diagnosis.result.provisional' => l10n.cropDoctorMessageProvisional,
    'diagnosis.result.confirmed' => l10n.cropDoctorMessageConfirmed,
    'diagnosis.result.corrected' => l10n.cropDoctorMessageCorrected,
    'diagnosis.result.unknown' => l10n.cropDoctorMessageUnknown,
    _ => switch (d.status) {
      DiagnosisStatus.confirmed => l10n.cropDoctorMessageConfirmed,
      DiagnosisStatus.corrected => l10n.cropDoctorMessageCorrected,
      DiagnosisStatus.provisional => l10n.cropDoctorMessageProvisional,
      _ =>
        d.problem == null
            ? l10n.cropDoctorMessageUnknown
            : l10n.cropDoctorMessageAnswered,
    },
  };
}

/// F28 title for an out-of-scope reason.
String diagnosisOutOfScopeTitle(CoreLocalizations l10n, String? reason) =>
    switch (reason) {
      'not_a_plant' => l10n.cropDoctorOutNotPlant,
      'unsupported_crop' => l10n.cropDoctorOutUnsupportedCrop,
      'unreadable_image' => l10n.cropDoctorOutUnreadable,
      'expert_not_diagnosable' => l10n.cropDoctorOutNotDiagnosable,
      _ => l10n.cropDoctorOutNoMatch,
    };

/// Confidence words for a history entry.
String diagnosisConfidenceWord(CoreLocalizations l10n, String? confidence) =>
    switch (confidence) {
      'high' => l10n.confidenceHigh,
      'medium' => l10n.confidenceMedium,
      _ => l10n.confidenceLow,
    };

/// "3 km" / "0.8 km" from metres.
String formatKm(double metres) {
  final km = metres / 1000;
  return km >= 10 ? km.round().toString() : km.toStringAsFixed(1);
}

/// The result of a diagnosis for F25 / F26 / F27 / F28 and A43: problem
/// card with the confidence in words and the symptom checklist, Organic /
/// Chemical treatments (dose per acre and per 15 L tank, PHI, PPE, safety
/// text) with ranked products at the store, cultural practices, the
/// "updated" banner and the earlier answers.
///
/// Order buttons appear only when [Diagnosis.showBuy] is true **and**
/// [onOrder] is given (SPEC 3.4: never on a provisional result).
class DiagnosisResultView extends StatefulWidget {
  /// Creates the view.
  const DiagnosisResultView({
    required this.diagnosis,
    this.photo,
    this.storeLabel,
    this.onOrder,
    this.orderLabel,
    this.showUpdatedBanner = false,
    this.tankPictogram = true,
    this.header,
    this.footer,
    super.key,
  });

  /// The diagnosis.
  final Diagnosis diagnosis;

  /// The user's photo.
  final ImageProvider<Object>? photo;

  /// "FCC Kondapur, 3 km" (the screen knows the distance).
  final String? storeLabel;

  /// Orders one product (the SKU and its label claim).
  final void Function(ProductOption option)? onOrder;

  /// Label of the per-product order button.
  final String? orderLabel;

  /// F27 banner.
  final bool showUpdatedBanner;

  /// Draw the per-tank dose as a tank.
  final bool tankPictogram;

  /// Extra content above the result (scouting: farmer and plot).
  final Widget? header;

  /// Extra content below (scouting: model version).
  final Widget? footer;

  @override
  State<DiagnosisResultView> createState() => _DiagnosisResultViewState();
}

class _DiagnosisResultViewState extends State<DiagnosisResultView> {
  final Set<int> _ticked = <int>{};
  TreatmentKind? _kind;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final d = widget.diagnosis;
    final children = <Widget>[
      ?widget.header,
      if (widget.showUpdatedBanner) _UpdatedBanner(diagnosis: d),
    ];
    if (d.isOutOfScope) {
      children.add(
        Container(
          key: DiagnosisKeys.outOfScope,
          padding: const EdgeInsets.all(Tokens.space4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Tokens.radiusCard),
            border: Border.fromBorderSide(app.borderSide),
          ),
          child: Column(
            children: <Widget>[
              Icon(
                d.outOfScopeReason == 'not_a_plant'
                    ? Icons.no_photography_outlined
                    : Icons.help_outline,
                size: 64,
                color: p.statusWarning,
              ),
              const SizedBox(height: Tokens.space3),
              Text(
                diagnosisHeadline(l10n, d),
                textAlign: TextAlign.center,
                style: app.text.title,
              ),
              const SizedBox(height: Tokens.space2),
              Text(
                l10n.cropDoctorOutHelp,
                textAlign: TextAlign.center,
                style: app.text.body,
              ),
            ],
          ),
        ),
      );
    } else if (d.problem != null) {
      final problem = d.problem!;
      final symptoms = problem.symptomsIn(lang);
      final name = problem.nameIn(lang);
      final english = problem.nameIn('en');
      children.addAll(<Widget>[
        Text(
          diagnosisHeadline(l10n, d),
          key: const Key('diagnosis-headline'),
          style: app.text.heading,
        ),
        const SizedBox(height: Tokens.space2),
        DiagnosisResultCard(
          problemName: name,
          localName: lang == 'en' || english == name ? null : english,
          confidence:
              d.confidence ??
              (d.provisional ? ConfidenceLevel.low : ConfidenceLevel.high),
          provisionalState: d.provisional,
          image: widget.photo,
          symptoms: <SymptomCheck>[
            for (final (i, s) in symptoms.indexed)
              SymptomCheck(label: s, present: _ticked.contains(i)),
          ],
          onSymptomTap: (i) => setState(
            () => _ticked.contains(i) ? _ticked.remove(i) : _ticked.add(i),
          ),
        ),
        const SizedBox(height: Tokens.space4),
        ..._treatments(context, d, lang),
      ]);
    } else {
      children.add(
        Text(
          diagnosisHeadline(l10n, d),
          key: const Key('diagnosis-headline'),
          style: app.text.heading,
        ),
      );
    }
    if (d.history.isNotEmpty) {
      children.addAll(<Widget>[
        const SizedBox(height: Tokens.space4),
        Text(l10n.cropDoctorHistoryTitle, style: app.text.heading),
        for (final h in d.history.reversed)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Row(
              children: <Widget>[
                Icon(Icons.history, color: p.textSecondary),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    l10n.cropDoctorEarlierAnswer(
                      '${h.nameIn(lang) ?? diagnosisOutOfScopeTitle(l10n, null)}'
                      ' · ${diagnosisConfidenceWord(l10n, h.confidence)}',
                    ),
                    style: app.text.body.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ]);
    }
    if (widget.footer != null) {
      children.addAll(<Widget>[
        const SizedBox(height: Tokens.space3),
        widget.footer!,
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Widget> _treatments(BuildContext context, Diagnosis d, String lang) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final kinds = <TreatmentKind>[
      if (d.organic.isNotEmpty) TreatmentKind.organic,
      if (d.chemical.isNotEmpty) TreatmentKind.chemical,
    ];
    final cultural = d.culturalIn(lang);
    final out = <Widget>[];
    if (kinds.isEmpty) {
      out.add(
        Text(
          l10n.cropDoctorNoProducts,
          key: const Key('diagnosis-no-products'),
          style: app.text.body.copyWith(color: p.textSecondary),
        ),
      );
    } else {
      final kind = kinds.contains(_kind) ? _kind! : kinds.first;
      out.add(
        SegmentedButton<TreatmentKind>(
          key: const Key('diagnosis-treatment-tabs'),
          showSelectedIcon: false,
          segments: <ButtonSegment<TreatmentKind>>[
            ButtonSegment<TreatmentKind>(
              value: TreatmentKind.organic,
              enabled: d.organic.isNotEmpty,
              icon: const Icon(Icons.spa_outlined),
              label: Text(l10n.treatmentOrganic),
            ),
            ButtonSegment<TreatmentKind>(
              value: TreatmentKind.chemical,
              enabled: d.chemical.isNotEmpty,
              icon: const Icon(Icons.science_outlined),
              label: Text(l10n.treatmentChemical),
            ),
          ],
          selected: <TreatmentKind>{kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
      );
      if (widget.storeLabel != null) {
        out.addAll(<Widget>[
          const SizedBox(height: Tokens.space3),
          Row(
            key: DiagnosisKeys.store,
            children: <Widget>[
              Icon(Icons.store_outlined, color: p.primary),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Text(
                  l10n.cropDoctorProductsAt(widget.storeLabel!),
                  style: app.text.label,
                ),
              ),
            ],
          ),
        ]);
      }
      final options = kind == TreatmentKind.organic ? d.organic : d.chemical;
      final canOrder = d.showBuy && widget.onOrder != null;
      for (final o in options) {
        out.addAll(<Widget>[
          const SizedBox(height: Tokens.space3),
          TreatmentCard(
            key: DiagnosisKeys.treatment(o.skuId),
            name: o.activeIngredient ?? o.productName,
            kind: o.kind,
            dosePerAcre: o.dosePerAcre ?? '—',
            dosePerTank: o.dosePerTank15l ?? '—',
            safetyIntervalDays: o.phiDays,
            ppe: o.ppe,
            safetyText: o.safetyText,
            tankPictogram: widget.tankPictogram,
          ),
          const SizedBox(height: Tokens.space2),
          ProductCard(
            name: o.productName,
            pack: o.packLabel,
            pricePaise: o.pricePaise,
            ownBrand: o.ownBrand,
            stockCount: o.stockQty ?? (o.inStock ? null : 0),
            storeName: widget.storeLabel ?? d.store?.name,
            showAction: canOrder,
            actionKey: DiagnosisKeys.orderProduct(o.skuId),
            actionLabel: widget.orderLabel ?? l10n.cropDoctorOrder,
            actionIcon: Icons.shopping_bag_outlined,
            onAdd: canOrder ? () => widget.onOrder!(o) : null,
          ),
        ]);
      }
    }
    if (cultural.isNotEmpty) {
      out.addAll(<Widget>[
        const SizedBox(height: Tokens.space4),
        Text(l10n.cropDoctorCulturalTitle, style: app.text.heading),
        for (final c in cultural)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.agriculture_outlined, color: p.statusSuccess),
                const SizedBox(width: Tokens.space2),
                Expanded(child: Text(c, style: app.text.body)),
              ],
            ),
          ),
      ]);
    }
    return out;
  }
}

class _UpdatedBanner extends StatelessWidget {
  const _UpdatedBanner({required this.diagnosis});

  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space3),
      child: Container(
        key: DiagnosisKeys.updatedBanner,
        padding: const EdgeInsets.all(Tokens.space3),
        decoration: BoxDecoration(
          color: app.tint(p.statusInfoContainer),
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          border: Border.all(color: p.statusInfo, width: app.borderWidth),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.notifications_active_outlined, color: p.statusInfo),
            const SizedBox(width: Tokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.cropDoctorUpdatedTitle, style: app.text.heading),
                  Text(
                    diagnosis.status == DiagnosisStatus.corrected
                        ? l10n.cropDoctorMessageCorrected
                        : l10n.cropDoctorMessageConfirmed,
                    style: app.text.body,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bottom actions of a result (FM-006 one-tap actions, SPEC 3.4):
///
/// * buy allowed ([Diagnosis.showBuy]): **Order** + call the officer;
/// * provisional / unknown: **Talk to your field officer** + ask an
///   expert — never a buy action;
/// * out of scope (F28): **Ask an expert** + call the officer.
class DiagnosisActionBar extends StatelessWidget {
  /// Creates the bar.
  const DiagnosisActionBar({
    required this.diagnosis,
    this.onOrder,
    this.orderLabel,
    this.onCallOfficer,
    this.callOfficerLabel,
    this.onAskExpert,
    this.talkLabel,
    super.key,
  });

  /// "Talk to your field officer" by default; the officer app says "Call
  /// farmer" (the officer is the one to talk to).
  final String? talkLabel;

  /// The diagnosis.
  final Diagnosis diagnosis;

  /// Orders the recommended product; only offered when buy is allowed.
  final VoidCallback? onOrder;

  /// "Order" / "Create order for farmer".
  final String? orderLabel;

  /// Calls the field officer (farmer) or the farmer (officer).
  final VoidCallback? onCallOfficer;

  /// Label of [onCallOfficer] when buy is allowed ("Call my officer").
  final String? callOfficerLabel;

  /// FM-006 ask an expert.
  final VoidCallback? onAskExpert;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final d = diagnosis;
    final buttons = <Widget>[];
    if (d.isOutOfScope) {
      buttons.addAll(<Widget>[
        AppButton(
          key: DiagnosisKeys.askExpert,
          label: l10n.cropDoctorAskExpert,
          icon: Icons.support_agent,
          onPressed: onAskExpert,
        ),
        if (onCallOfficer != null)
          AppButton(
            key: DiagnosisKeys.talkToOfficer,
            label: talkLabel ?? l10n.cropDoctorTalkToOfficer,
            icon: Icons.call_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: onCallOfficer,
          ),
      ]);
    } else if (d.showBuy && onOrder != null && d.recommended != null) {
      buttons.addAll(<Widget>[
        AppButton(
          key: DiagnosisKeys.buy,
          label: orderLabel ?? l10n.cropDoctorOrder,
          icon: Icons.shopping_bag_outlined,
          onPressed: onOrder,
        ),
        AppButton(
          key: DiagnosisKeys.talkToOfficer,
          label: callOfficerLabel ?? l10n.cropDoctorCallOfficer,
          icon: Icons.call_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: onCallOfficer,
        ),
      ]);
    } else {
      buttons.addAll(<Widget>[
        AppButton(
          key: DiagnosisKeys.talkToOfficer,
          label: talkLabel ?? l10n.cropDoctorTalkToOfficer,
          icon: Icons.call_outlined,
          onPressed: onCallOfficer,
        ),
        if (onAskExpert != null && !d.status.isWaiting)
          AppButton(
            key: DiagnosisKeys.askExpert,
            label: l10n.cropDoctorAskExpert,
            icon: Icons.support_agent,
            variant: AppButtonVariant.secondary,
            onPressed: onAskExpert,
          ),
      ]);
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(Tokens.space3),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: app.borderSide),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (i, b) in buttons.indexed) ...<Widget>[
              if (i > 0) const SizedBox(height: Tokens.space2),
              b,
            ],
          ],
        ),
      ),
    );
  }
}
