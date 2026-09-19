// FM-005 / SPEC 3.4 / DX-009 on the shared result view: confidence in
// words, symptom checklist, Organic / Chemical, dose per acre and per 15 L
// tank, PHI and PPE on every chemical option, and never a buy action on a
// provisional or out-of-scope result.
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

Diagnosis _d(FakeDiagnosisOutcome o, {String? status}) => Diagnosis.fromData(
  'dx-1',
  FakeDiagnosisServer.diagnosisOut(id: 'dx-1', outcome: o, status: status),
);

Widget _screen(
  Diagnosis d, {
  List<ProductOption>? ordered,
  Locale locale = const Locale('en'),
  bool banner = false,
}) => harness(
  locale: locale,
  padded: false,
  Column(
    children: <Widget>[
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            DiagnosisResultView(
              diagnosis: d,
              storeLabel: 'FCC Kondapur, 3.0 km',
              showUpdatedBanner: banner,
              onOrder: ordered?.add,
            ),
          ],
        ),
      ),
      DiagnosisActionBar(
        diagnosis: d,
        onOrder: ordered == null ? null : () => ordered.add(d.recommended!),
        onCallOfficer: () {},
        onAskExpert: () {},
      ),
    ],
  ),
);

void _noBuy() {
  expect(find.byKey(DiagnosisKeys.buy), findsNothing);
  expect(find.byKey(DiagnosisKeys.orderProduct('sku-azoxy')), findsNothing);
  expect(find.byKey(DiagnosisKeys.orderProduct('sku-neem')), findsNothing);
  expect(find.text('Order'), findsNothing);
  expect(find.text('Add'), findsNothing);
}

void main() {
  testWidgets('high confidence: words, symptoms, products and Order', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final ordered = <ProductOption>[];
    await tester.pumpWidget(
      _screen(_d(FakeDiagnosisOutcome.high), ordered: ordered),
    );
    expect(find.text('High confidence'), findsOneWidget);
    expect(find.text('We found the problem'), findsOneWidget);
    expect(find.text('Anthracnose (fruit rot)'), findsOneWidget);
    expect(find.text('Sunken dark spots on the fruit'), findsOneWidget);
    // Symptom rows are ticked by the user.
    await tester.tap(find.byKey(const Key('diagnosis-symptom-0')));
    await tester.pump();
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    expect(find.byKey(DiagnosisKeys.buy), findsOneWidget);
    await tester.tap(find.byKey(DiagnosisKeys.buy));
    expect(ordered.single.skuId, 'sku-azoxy');
    expect(ordered.single.labelClaimId, 'lc-azoxy');
  });

  testWidgets('every chemical option shows dose per acre, per tank, PHI, PPE', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      _screen(_d(FakeDiagnosisOutcome.high), ordered: <ProductOption>[]),
    );
    await tester.ensureVisible(find.text('Chemical'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chemical'));
    await tester.pumpAndSettle();
    for (final (sku, acre, tank, phi) in <(String, String, String, int)>[
      ('sku-azoxy', '200 ml', '15 ml', 5),
      ('sku-mitra-myclo', '160 g', '12 g', 7),
    ]) {
      final card = find.byKey(DiagnosisKeys.treatment(sku));
      await tester.scrollUntilVisible(card, 200);
      expect(
        find.descendant(of: card, matching: find.text(acre)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text(tank)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const Key('treatment-tank')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('Wait $phi days before harvest'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Gloves')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Mask')),
        findsOneWidget,
      );
    }
    final azoxy = find.byKey(DiagnosisKeys.treatment('sku-azoxy'));
    expect(
      find.descendant(of: azoxy, matching: find.text('Goggles')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: azoxy, matching: find.text('Full sleeves')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: azoxy,
        matching: find.byKey(const Key('treatment-safety-text')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('provisional: expert note, officer CTA, no buy action anywhere', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      _screen(_d(FakeDiagnosisOutcome.provisional), ordered: <ProductOption>[]),
    );
    expect(find.text('Provisional — expert will confirm'), findsOneWidget);
    expect(
      find.text('Our expert will confirm within 24 hours'),
      findsOneWidget,
    );
    expect(find.text('Medium confidence'), findsOneWidget);
    expect(find.text('Talk to your field officer'), findsOneWidget);
    _noBuy();
    // Treatments are still shown (dose, PHI, PPE), only the buy is gone.
    await tester.ensureVisible(find.text('Chemical'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chemical'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(DiagnosisKeys.treatment('sku-azoxy')),
      200,
    );
    _noBuy();
  });

  testWidgets('out of scope (F28): friendly message and ask an expert', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      _screen(_d(FakeDiagnosisOutcome.notAPlant), ordered: <ProductOption>[]),
    );
    expect(find.byKey(DiagnosisKeys.outOfScope), findsOneWidget);
    expect(find.text('We could not see a plant in the photo'), findsOneWidget);
    expect(find.byKey(DiagnosisKeys.askExpert), findsOneWidget);
    _noBuy();
  });

  testWidgets('F27 banner and the earlier answer', (tester) async {
    usePhoneSurface(tester);
    final out = FakeDiagnosisServer.diagnosisOut(
      id: 'dx-1',
      outcome: FakeDiagnosisOutcome.high,
      status: 'confirmed',
    );
    out['_local'] = <String, Object?>{
      'history': <Object?>[
        const DiagnosisHistoryEntry(
          status: DiagnosisStatus.provisional,
          confidence: 'medium',
          problemNames: <String, String>{'en': 'Anthracnose (fruit rot)'},
        ).toJson(),
      ],
      'update_unseen': true,
    };
    final d = Diagnosis.fromData('dx-1', out);
    await tester.pumpWidget(
      _screen(d, banner: true, ordered: <ProductOption>[]),
    );
    expect(find.byKey(DiagnosisKeys.updatedBanner), findsOneWidget);
    expect(find.text('Your result was updated'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Earlier answers'), 200);
    expect(
      find.text('Earlier: Anthracnose (fruit rot) · Medium confidence'),
      findsOneWidget,
    );
    expect(find.byKey(DiagnosisKeys.buy), findsOneWidget);
  });

  testWidgets('problem name in the farmer language with English below', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      _screen(
        _d(FakeDiagnosisOutcome.high),
        ordered: <ProductOption>[],
        locale: const Locale('te'),
      ),
    );
    expect(find.text('కాయ కుళ్ళు తెగులు'), findsOneWidget);
    expect(find.text('Anthracnose (fruit rot)'), findsOneWidget);
    expect(find.text('కాయలపై లోతైన నల్లని మచ్చలు'), findsOneWidget);
  });
}
