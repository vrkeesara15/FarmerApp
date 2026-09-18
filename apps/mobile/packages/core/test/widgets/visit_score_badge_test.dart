import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  group('VisitStatus.fromScore', () {
    test('verified at or above 70', () {
      expect(VisitStatus.fromScore(100), VisitStatus.verified);
      expect(VisitStatus.fromScore(70), VisitStatus.verified);
    });

    test('partial between 40 and 69', () {
      expect(VisitStatus.fromScore(69), VisitStatus.partial);
      expect(VisitStatus.fromScore(40), VisitStatus.partial);
    });

    test('unverified below 40', () {
      expect(VisitStatus.fromScore(39), VisitStatus.unverified);
      expect(VisitStatus.fromScore(0), VisitStatus.unverified);
    });
  });

  testWidgets('renders the localised status label and score', (tester) async {
    await tester.pumpWidget(harness(const VisitScoreBadge(score: 85)));
    expect(find.text('85'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);

    await tester.pumpWidget(harness(const VisitScoreBadge(score: 55)));
    expect(find.text('Partial'), findsOneWidget);

    await tester.pumpWidget(harness(const VisitScoreBadge(score: 12)));
    expect(find.text('Unverified'), findsOneWidget);
  });

  testWidgets('Telugu locale still resolves strings (falls back)', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const VisitScoreBadge(score: 85), locale: const Locale('te')),
    );
    expect(find.text('85'), findsOneWidget);
  });
}
