// Golden tests for every design-system widget in Light and Sunlight at
// 360x800 logical px. Regenerate with:
//   flutter test --update-goldens test/goldens
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

typedef _Case = (String name, Widget Function() build);

final DateTime _visitTime = DateTime.utc(2026, 9, 17, 4, 30);
final DateTime _dueDate = DateTime.utc(2030, 1, 15);

void _noop() {}

final List<_Case> _cases = <_Case>[
  (
    'app_button',
    () => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppButton(label: 'Primary', onPressed: _noop),
        SizedBox(height: Tokens.space3),
        AppButton(
          label: 'Secondary',
          variant: AppButtonVariant.secondary,
          icon: Icons.add,
          onPressed: _noop,
        ),
        SizedBox(height: Tokens.space3),
        AppButton(
          label: 'Tertiary',
          variant: AppButtonVariant.tertiary,
          size: AppButtonSize.medium,
          onPressed: _noop,
        ),
        SizedBox(height: Tokens.space3),
        AppButton(
          label: 'Delete',
          variant: AppButtonVariant.destructive,
          icon: Icons.delete_outline,
          onPressed: _noop,
        ),
        SizedBox(height: Tokens.space3),
        AppButton(label: 'Disabled', onPressed: null),
        SizedBox(height: Tokens.space3),
        AppButton(label: 'Loading', loading: true, onPressed: _noop),
        SizedBox(height: Tokens.space3),
        Row(
          children: <Widget>[
            AppButton(
              label: 'Medium',
              size: AppButtonSize.medium,
              expand: false,
              onPressed: _noop,
            ),
            SizedBox(width: Tokens.space3),
            AppButton(
              label: 'Icon',
              size: AppButtonSize.medium,
              icon: Icons.camera_alt_outlined,
              expand: false,
              variant: AppButtonVariant.secondary,
              onPressed: _noop,
            ),
          ],
        ),
      ],
    ),
  ),
  (
    'app_text_field',
    () => Column(
      children: <Widget>[
        AppTextField(
          label: 'Mobile number',
          indiaPhone: true,
          helperText: 'We will send a 6-digit OTP by SMS',
          controller: TextEditingController(text: '9876543210'),
        ),
        const SizedBox(height: Tokens.space4),
        const AppTextField(
          label: 'Farmer name',
          hintText: 'Ramesh Reddy',
          prefixIcon: Icons.person_outline,
        ),
        const SizedBox(height: Tokens.space4),
        AppTextField(
          label: 'Village',
          errorText: 'Village is required',
          controller: TextEditingController(text: 'Kondapur'),
        ),
        const SizedBox(height: Tokens.space4),
        AppTextField(
          label: 'Disabled',
          enabled: false,
          controller: TextEditingController(text: 'Read only'),
        ),
      ],
    ),
  ),
  (
    'otp_input',
    () => const Column(
      children: <Widget>[
        OtpInput(autofocus: false),
        SizedBox(height: Tokens.space6),
        OtpInput(
          autofocus: false,
          errorText: 'Incorrect OTP. Please try again.',
          resendAfter: Duration.zero,
        ),
      ],
    ),
  ),
  (
    'language_picker',
    () => LanguagePicker(
      selected: const Locale('te'),
      onSelected: (_) {},
      onPlayAudio: (_) {},
    ),
  ),
  (
    'duty_toggle',
    () => Column(
      children: <Widget>[
        DutyToggle(onDuty: false, onChanged: (_) {}),
        const SizedBox(height: Tokens.space4),
        DutyToggle(
          onDuty: true,
          elapsed: const Duration(hours: 3, minutes: 12),
          onChanged: (_) {},
        ),
        const SizedBox(height: Tokens.space4),
        DutyToggle(onDuty: false, loading: true, onChanged: (_) {}),
      ],
    ),
  ),
  (
    'stat_tile',
    () => const Row(
      children: <Widget>[
        Expanded(
          child: StatTile(
            value: '12',
            label: 'Visits verified',
            icon: Icons.verified_outlined,
            trend: StatTrend.up,
            trendLabel: '+3',
          ),
        ),
        SizedBox(width: Tokens.space3),
        Expanded(
          child: StatTile(
            value: '₹1,25,000',
            label: 'Collections',
            icon: Icons.currency_rupee,
            trend: StatTrend.down,
          ),
        ),
      ],
    ),
  ),
  (
    'farmer_card',
    () => Column(
      children: <Widget>[
        FarmerCard(
          name: 'Ramesh Reddy',
          village: 'Kondapur',
          crops: const <CropChipData>[
            CropChipData(name: 'Cotton', stage: 'Flowering'),
            CropChipData(
              name: 'Chilli',
              stage: 'Sowing',
              icon: Icons.whatshot_outlined,
            ),
          ],
          lastVisitUtc: _visitTime,
          balanceDuePaise: 450000,
          onTap: _noop,
        ),
        const SizedBox(height: Tokens.space3),
        const FarmerCard(name: 'Lakshmi Devi', village: 'Peddapalli'),
      ],
    ),
  ),
  (
    'crop_chip',
    () => const Wrap(
      spacing: Tokens.space2,
      runSpacing: Tokens.space2,
      children: <Widget>[
        CropChip(
          data: CropChipData(name: 'Cotton', stage: 'Flowering'),
        ),
        CropChip(
          data: CropChipData(name: 'Paddy', icon: Icons.grass),
        ),
        CropChip(
          data: CropChipData(name: 'Chilli', stage: 'Sowing'),
          selected: true,
          onTap: _noop,
        ),
      ],
    ),
  ),
  (
    'stage_timeline',
    () => const StageTimeline(
      stages: <String>['Sowing', 'Growing', 'Flowering', 'Fruiting', 'Harvest'],
      currentIndex: 2,
    ),
  ),
  (
    'visit_card',
    () => Column(
      children: <Widget>[
        VisitCard(
          farmerName: 'Ramesh Reddy',
          purpose: VisitPurpose.scouting,
          startedAtUtc: _visitTime,
          duration: const Duration(minutes: 24),
          score: 86,
          onTap: _noop,
        ),
        const SizedBox(height: Tokens.space3),
        VisitCard(
          farmerName: 'Lakshmi Devi',
          purpose: VisitPurpose.collection,
          startedAtUtc: _visitTime,
          duration: const Duration(minutes: 6),
          score: 32,
        ),
      ],
    ),
  ),
  (
    'visit_score_badge',
    () => const Wrap(
      spacing: Tokens.space2,
      runSpacing: Tokens.space2,
      children: <Widget>[
        VisitScoreBadge(score: 92),
        VisitScoreBadge(score: 70),
        VisitScoreBadge(score: 55),
        VisitScoreBadge(score: 40),
        VisitScoreBadge(score: 12),
      ],
    ),
  ),
  (
    'proof_checklist',
    () => const ProofChecklist(
      items: <ProofItem>[
        ProofItem(kind: ProofKind.geofence, satisfied: true),
        ProofItem(kind: ProofKind.photo, satisfied: true),
        ProofItem(kind: ProofKind.farmerConfirmed, satisfied: false),
        ProofItem(kind: ProofKind.duration, satisfied: false),
      ],
    ),
  ),
  (
    'camera_guide_overlay',
    () => const SizedBox(
      height: 700,
      child: ColoredBox(color: Color(0xFF3A3A3A), child: CameraGuideOverlay()),
    ),
  ),
  (
    'diagnosis_result_card',
    () => const Column(
      children: <Widget>[
        DiagnosisResultCard(
          problemName: 'Pink bollworm',
          localName: 'గులాబీ రంగు పురుగు',
          confidence: ConfidenceLevel.high,
          symptoms: <SymptomCheck>[
            SymptomCheck(label: 'Rosette flowers', present: true),
            SymptomCheck(label: 'Holes in bolls', present: true),
            SymptomCheck(label: 'Yellow leaves', present: false),
          ],
        ),
        SizedBox(height: Tokens.space3),
        DiagnosisResultCard(
          problemName: 'Leaf curl (suspected)',
          confidence: ConfidenceLevel.low,
        ),
      ],
    ),
  ),
  (
    'confidence_band',
    () => const Wrap(
      spacing: Tokens.space2,
      children: <Widget>[
        ConfidenceBand(level: ConfidenceLevel.high),
        ConfidenceBand(level: ConfidenceLevel.medium),
        ConfidenceBand(level: ConfidenceLevel.low),
      ],
    ),
  ),
  (
    'treatment_card',
    () => const Column(
      children: <Widget>[
        TreatmentCard(
          name: 'Neem oil spray',
          kind: TreatmentKind.organic,
          dosePerAcre: '1 L',
          dosePerTank: '75 ml',
        ),
        SizedBox(height: Tokens.space3),
        TreatmentCard(
          name: 'Confidor',
          kind: TreatmentKind.chemical,
          activeIngredient: 'Imidacloprid 17.8% SL',
          dosePerAcre: '100 ml',
          dosePerTank: '5 ml',
          safetyIntervalDays: 21,
          ppe: <Ppe>{Ppe.gloves, Ppe.mask, Ppe.goggles},
        ),
      ],
    ),
  ),
  (
    'product_card',
    () => const Column(
      children: <Widget>[
        ProductCard(
          name: 'FCC Neem Gold 1500 ppm',
          pack: '1 L',
          pricePaise: 45000,
          ownBrand: true,
          stockCount: 12,
          storeName: 'FCC Kondapur',
          onAdd: _noop,
        ),
        SizedBox(height: Tokens.space3),
        ProductCard(
          name: 'Confidor 17.8% SL',
          pack: '250 ml',
          pricePaise: 62500,
          stockCount: 0,
          storeName: 'FCC Kondapur',
          onAdd: _noop,
        ),
        SizedBox(height: Tokens.space3),
        ProductCard(
          name: 'Urea 45 kg',
          pack: '45 kg',
          pricePaise: 26650,
          added: true,
          onAdd: _noop,
        ),
      ],
    ),
  ),
  (
    'own_brand_badge',
    () => const Align(alignment: Alignment.topLeft, child: OwnBrandBadge()),
  ),
  (
    'cart_bar',
    () => const Column(
      children: <Widget>[
        CartBar(itemCount: 3, totalPaise: 134150, onCheckout: _noop),
        SizedBox(height: Tokens.space4),
        CartBar(itemCount: 0, totalPaise: 0, onCheckout: null),
      ],
    ),
  ),
  (
    'payment_method_selector',
    () => PaymentMethodSelector(
      selected: PaymentMethod.upiQr,
      onChanged: (_) {},
      available: const <PaymentMethod>{
        PaymentMethod.upiQr,
        PaymentMethod.paymentLink,
        PaymentMethod.cash,
      },
      creditHint: 'Credit limit reached',
    ),
  ),
  (
    'upi_qr_panel',
    () => const UpiQrPanel(
      state: UpiPaymentState.waiting,
      amountPaise: 134150,
      qrPayload: 'upi://pay?pa=fcc@upi&am=1341.50',
      remaining: Duration(minutes: 4, seconds: 32),
    ),
  ),
  (
    'upi_qr_panel_paid',
    () => const UpiQrPanel(
      state: UpiPaymentState.paid,
      amountPaise: 134150,
      qrPayload: 'upi://pay?pa=fcc@upi&am=1341.50',
    ),
  ),
  (
    'upi_qr_panel_failed',
    () => const UpiQrPanel(
      state: UpiPaymentState.failed,
      amountPaise: 134150,
      qrPayload: 'upi://pay?pa=fcc@upi&am=1341.50',
      onRetry: _noop,
    ),
  ),
  (
    'khata_ledger',
    () => KhataLedger(
      balancePaise: 1250050,
      dueDateUtc: _dueDate,
      actionLabel: 'Collect',
      onAction: _noop,
      entries: <KhataEntry>[
        KhataEntry(
          dateUtc: _visitTime,
          description: 'Cash received',
          amountPaise: 200000,
          isCredit: true,
        ),
        KhataEntry(
          dateUtc: _visitTime,
          description: 'Confidor 250 ml x2',
          amountPaise: 125000,
          isCredit: false,
        ),
      ],
    ),
  ),
  ('offline_banner', () => const OfflineBanner()),
  (
    'sync_status_pill',
    () => const Wrap(
      spacing: Tokens.space2,
      children: <Widget>[
        SyncStatusPill(state: SyncState.synced),
        SyncStatusPill(state: SyncState.pending, pendingCount: 4),
        SyncStatusPill(state: SyncState.failed),
        SyncStatusPill(state: SyncState.syncing, pendingCount: 4),
      ],
    ),
  ),
  (
    'empty_state',
    () => const EmptyState(
      icon: Icons.groups_outlined,
      title: 'No farmers yet',
      help: 'Add your first farmer to start visits.',
      actionLabel: 'Add farmer',
      onAction: _noop,
    ),
  ),
  ('error_state', () => const ErrorState(onRetry: _noop)),
  (
    'skeletons',
    () => const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Skeletons.line(width: 200),
        SizedBox(height: Tokens.space3),
        Skeletons.card(),
        SizedBox(height: Tokens.space3),
        Skeletons.list(count: 2),
      ],
    ),
  ),
  (
    'rating',
    () => Column(
      children: <Widget>[
        Rating(value: 4, onChanged: (_) {}),
        const SizedBox(height: Tokens.space6),
        Rating(value: 3, style: RatingStyle.stars, onChanged: (_) {}),
      ],
    ),
  ),
  (
    'app_stepper',
    () => const AppStepper(
      steps: <String>['Basics', 'Farm boundary', 'Crops', 'Consent', 'Review'],
      currentIndex: 2,
    ),
  ),
  (
    'photo_review_card',
    () => const Column(
      children: <Widget>[
        PhotoReviewCard(
          sizeBytes: 186 * 1024,
          width: 1280,
          height: 960,
          index: 1,
          total: 3,
          quality: PhotoQualityResult(
            isBlurry: false,
            blurScore: 240,
            isTooDark: false,
            brightness: 0.45,
            tipKey: PhotoTipKeys.ok,
          ),
          onRetake: _noop,
          onUse: _noop,
        ),
        SizedBox(height: Tokens.space3),
        PhotoReviewCard(
          sizeBytes: 172 * 1024,
          width: 960,
          height: 1280,
          quality: PhotoQualityResult(
            isBlurry: true,
            blurScore: 12,
            isTooDark: false,
            brightness: 0.45,
            tipKey: PhotoTipKeys.blurry,
          ),
          onRetake: _noop,
          onUse: _noop,
        ),
        SizedBox(height: Tokens.space3),
        PhotoReviewCard(
          sizeBytes: 90 * 1024,
          width: 1280,
          height: 960,
          onRetake: _noop,
          onUse: _noop,
        ),
      ],
    ),
  ),
  (
    'camera_guide_overlay_tip',
    () => const SizedBox(
      height: 700,
      child: ColoredBox(
        color: Color(0xFF3A3A3A),
        child: CameraGuideOverlay(tipKey: PhotoTipKeys.blurry),
      ),
    ),
  ),
];

void main() {
  for (final mode in AppThemeMode.values) {
    group(mode.name, () {
      for (final (name, build) in _cases) {
        testWidgets(name, (tester) async {
          usePhoneSurface(tester);
          await tester.pumpWidget(
            harness(
              SingleChildScrollView(child: build()),
              mode: mode,
              padded: !name.startsWith('camera_guide_overlay'),
            ),
          );
          await tester.pump();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/${name}_${mode.name}.png'),
          );
        });
      }
    });
  }
}
