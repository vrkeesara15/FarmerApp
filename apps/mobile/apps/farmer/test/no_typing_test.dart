import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'kisan_harness.dart';

/// NF-010: no farmer flow needs typing beyond the phone number and the OTP.
/// Walks every route of the farmer app and asserts there is no text input
/// outside F02 (phone) and F03 (OTP), that those two are the *only* screens
/// allowed to ask, and that both of them open a number pad rather than a
/// letter keyboard.
///
/// The walk is shared with `a11y_test.dart` (NF-009) through [allPaths], so a
/// screen added to the router is covered by both the literacy gate and the
/// accessibility gate the moment it exists.

/// Every concrete path of [routes] (path parameters filled in).
List<String> allPaths(List<RouteBase> routes, [String parent = '']) {
  const params = <String, String>{
    ':skuId': 'sku-neem',
    ':id': 'o-1',
    ':visitId': 'v-1',
    ':cropPlotId': 'plot-1',
  };
  final out = <String>[];
  for (final r in routes) {
    if (r is! GoRoute) continue;
    var path = r.path.startsWith('/')
        ? r.path
        : '${parent == '/' ? '' : parent}/${r.path}';
    for (final e in params.entries) {
      path = path.replaceAll(e.key, e.value);
    }
    out
      ..add(path)
      ..addAll(allPaths(r.routes, path));
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final paths = allPaths(buildRouter().configuration.routes);

  test('typing is allowed on exactly two screens, and they are the two '
      'NF-010 names', () {
    // The requirement is a *closed* set, so the assertion is equality, not
    // containment: a third screen added to `typingAllowed` is the failure
    // this test exists to catch.
    expect(AppRoutes.typingAllowed, <String>{AppRoutes.phone, AppRoutes.otp});
  });

  testWidgets('the two typing screens ask for digits only, on a number pad', (
    tester,
  ) async {
    // "No flow requires typing beyond phone number and OTP" is only true if
    // those two are themselves reachable by a farmer who cannot read a
    // QWERTY keyboard: both must open the number pad.
    for (final path in AppRoutes.typingAllowed) {
      usePhoneSurface(tester);
      final deps = KisanDeps()..seedWorld();
      addTearDown(deps.dispose);
      await pumpApp(tester, deps.app(initialLocation: path));
      final fields = find.byType(EditableText, skipOffstage: false);
      expect(fields, findsWidgets, reason: '$path should ask for digits');
      for (final field in tester.widgetList<EditableText>(fields)) {
        expect(
          field.keyboardType,
          anyOf(TextInputType.phone, TextInputType.number),
          reason: '$path must open the number pad, not a letter keyboard',
        );
      }
    }
  });

  test('the walk covers every farmer screen', () {
    expect(paths, hasLength(greaterThanOrEqualTo(26)));
    expect(
      paths,
      containsAll(<String>[
        AppRoutes.language,
        AppRoutes.phone,
        AppRoutes.otp,
        AppRoutes.consent,
        AppRoutes.welcome,
        AppRoutes.home,
        AppRoutes.cropDoctor,
        AppRoutes.cropCamera,
        AppRoutes.cropCheck,
        AppRoutes.cropChoose,
        AppRoutes.cropResult('o-1'),
        AppRoutes.shop,
        AppRoutes.product('sku-neem'),
        AppRoutes.cart,
        AppRoutes.pay,
        AppRoutes.orders,
        AppRoutes.order('o-1'),
        AppRoutes.crops,
        AppRoutes.addCrop,
        AppRoutes.calendar('plot-1'),
        AppRoutes.weather,
        AppRoutes.alerts,
        AppRoutes.inbox,
        AppRoutes.khata,
        AppRoutes.receipt,
        AppRoutes.visit('v-1'),
        AppRoutes.visitRate('v-1'),
        AppRoutes.visitScan,
        AppRoutes.officer,
        AppRoutes.me,
        AppRoutes.consentSettings,
        AppRoutes.deleteAccount,
      ]),
    );
  });

  for (final path in paths) {
    testWidgets('route $path', (tester) async {
      usePhoneSurface(tester);
      final deps = KisanDeps()..seedWorld(khataBalance: 1000);
      deps.seedAdvisory();
      addTearDown(deps.dispose);
      await real(tester, () => deps.signIn(welcomeDone: false));
      await real(tester, deps.primeAdvisory);
      await pumpApp(tester, deps.app(initialLocation: path));
      final fields = find.byType(EditableText, skipOffstage: false);
      if (AppRoutes.typingAllowed.contains(path)) {
        expect(fields, findsOneWidget, reason: '$path: phone or OTP');
      } else {
        expect(fields, findsNothing, reason: '$path must not ask to type');
      }
    });
  }
}
