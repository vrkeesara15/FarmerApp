import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('required and optional cards toggle and read aloud', (
    tester,
  ) async {
    var granted = false;
    var readAloud = 0;
    await tester.pumpWidget(
      harness(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: <Widget>[
              ConsentCard(
                title: 'Use my data to give crop advice',
                body: 'We look at your crop photos.',
                notice: 'Plain-language notice',
                required: true,
                granted: granted,
                onChanged: (v) => setState(() => granted = v),
                onReadAloud: () => readAloud += 1,
                toggleKey: const Key('consent-data'),
              ),
              const ConsentCard(
                title: 'Send me offers and tips',
                body: 'Messages about products.',
                required: false,
                granted: false,
                onChanged: _ignore,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    expect(find.text('Plain-language notice'), findsOneWidget);
    expect(find.text('Read aloud'), findsNWidgets(2));
    await tester.tap(find.text('Read aloud').first);
    expect(readAloud, 1);
    await tester.tap(find.byKey(const Key('consent-data')));
    await tester.pumpAndSettle();
    expect(granted, isTrue);
    expect(
      find.bySemanticsLabel('Use my data to give crop advice, Required'),
      findsOneWidget,
    );
  });
}

void _ignore(bool _) {}
