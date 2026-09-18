import 'dart:io';

import 'package:farmerapp_mobile/string_lint.dart';
import 'package:test/test.dart';

List<String> _kinds(String source) =>
    lintSource(source).map((v) => '${v.kind}:${v.literal}').toList();

void main() {
  group('lintSource flags', () {
    test("Text('Hello'), Text(\"Hi\") and const Text", () {
      expect(_kinds("Text('Hello')"), <String>['Text:Hello']);
      expect(_kinds('Text("Hi")'), <String>['Text:Hi']);
      expect(_kinds("const Text('Hello')"), <String>['Text:Hello']);
      expect(_kinds("Text(\n  'Multi',\n)"), <String>['Text:Multi']);
    });

    test('label: on known widgets', () {
      expect(_kinds("AppButton(label: 'Send OTP', onPressed: f)"), <String>[
        'label:Send OTP',
      ]);
      expect(_kinds("AppTextField(label: 'Phone')"), <String>['label:Phone']);
    });

    test('tooltip:, hintText:, helperText:, errorText:, semanticsLabel:', () {
      expect(_kinds("IconButton(tooltip: 'Listen', onPressed: f)"), <String>[
        'tooltip:Listen',
      ]);
      expect(_kinds("InputDecoration(hintText: 'Search')"), <String>[
        'hintText:Search',
      ]);
      expect(_kinds("helperText: 'We send an SMS'"), <String>[
        'helperText:We send an SMS',
      ]);
      expect(_kinds("errorText: 'Wrong OTP'"), <String>['errorText:Wrong OTP']);
      expect(_kinds("Image(semanticsLabel: 'Leaf')"), <String>[
        'semanticsLabel:Leaf',
      ]);
      expect(_kinds("Icon(semanticLabel: 'Leaf')"), <String>[
        'semanticLabel:Leaf',
      ]);
    });

    test('reports the 1-based line number and path', () {
      final v = lintSource("import 'a.dart';\n\nText('x');\n", path: 'p.dart');
      expect(v.single.line, 3);
      expect(v.single.path, 'p.dart');
      expect(v.single.toString(), "p.dart:3: Text('x')");
    });
  });

  group('lintSource allows', () {
    test('a trailing // i18n-ignore', () {
      expect(_kinds("Text('Mitra') // i18n-ignore"), isEmpty);
      expect(_kinds("label: 'x', // i18n-ignore"), isEmpty);
    });

    test('// i18n-ignore on the previous line', () {
      expect(_kinds("// i18n-ignore: brand name\nText('Mitra')"), isEmpty);
    });

    test('// i18n-ignore-file', () {
      expect(_kinds("// i18n-ignore-file\nText('a');\nlabel: 'b'"), isEmpty);
    });

    test('literals without letters or made only of interpolations', () {
      expect(_kinds("Text('+91')"), isEmpty);
      expect(_kinds("Text('—')"), isEmpty);
      expect(_kinds("Text('12:30')"), isEmpty);
      expect(_kinds(r"Text('$count')"), isEmpty);
      expect(_kinds(r"Text('${a.b}, $c')"), isEmpty);
      expect(_kinds(r"label: '${option.nativeName}, $englishName'"), isEmpty);
    });

    test('values that come from l10n or variables', () {
      expect(_kinds('Text(l10n.title)'), isEmpty);
      expect(_kinds('AppButton(label: l10n.actionContinue)'), isEmpty);
      expect(_kinds('tooltip: label,'), isEmpty);
    });

    test('unrelated arguments with a similar name', () {
      expect(_kinds("HttpAuthApi(deviceName: 'Mitra Android')"), isEmpty);
      expect(_kinds('Semantics(label: name)'), isEmpty);
    });
  });

  group('files', () {
    test('generated code is skipped', () {
      expect(isLinted('lib/src/a.g.dart'), isFalse);
      expect(isLinted('lib/src/i18n/generated/x.dart'), isFalse);
      expect(isLinted('lib/src/widgets/x.dart'), isTrue);
      expect(isLinted('lib/README.md'), isFalse);
    });

    test('lintDirectory walks a tree and reports relative paths', () async {
      final tmp = await Directory.systemTemp.createTemp('string_lint_');
      addTearDown(() => tmp.delete(recursive: true));
      final sub = Directory('${tmp.path}/lib/screens')
        ..createSync(recursive: true);
      File('${sub.path}/bad.dart').writeAsStringSync("Text('Hello')\n");
      File('${sub.path}/good.dart').writeAsStringSync('Text(l10n.hi)\n');
      File('${sub.path}/gen.g.dart').writeAsStringSync("Text('Skipped')\n");
      final result = lintDirectory(
        Directory('${tmp.path}/lib'),
        relativeTo: tmp,
      );
      expect(result.scanned, 2);
      expect(result.violations.map((v) => v.toString()), <String>[
        "lib/screens/bad.dart:1: Text('Hello')",
      ]);
    });

    test('scanRoots covers every app and the core widgets', () async {
      final tmp = await Directory.systemTemp.createTemp('string_lint_');
      addTearDown(() => tmp.delete(recursive: true));
      Directory('${tmp.path}/apps/agent/lib').createSync(recursive: true);
      Directory('${tmp.path}/apps/farmer/lib').createSync(recursive: true);
      final roots = scanRoots(tmp)
          .map((d) => d.path.substring(tmp.path.length));
      expect(roots, <String>[
        '/packages/core/lib/src/widgets',
        '/apps/agent/lib',
        '/apps/farmer/lib',
      ]);
    });
  });
}
