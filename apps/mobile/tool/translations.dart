// NF-008 translation review pack: export the ARB files for a native-speaker
// review, and import the reviewed sheets back.
//
// "All farmer-facing text reviewed by a native speaker" is the last open half
// of NF-008 and it is a human gate. This is the tooling that makes the gate
// passable: the reviewer gets a spreadsheet with the English, the current
// translation, the placeholders that must survive and the screens the string
// appears on; we get their answer back as a checked ARB diff.
//
// Usage (from apps/mobile):
//   dart run tool/translations.dart export            # all four languages
//   dart run tool/translations.dart export --locale te --out ../../review
//   dart run tool/translations.dart import build/i18n/review_te.csv
//   dart run tool/translations.dart import build/i18n/review_te.csv --dry-run
//
// Export writes build/i18n/review_<locale>.csv by default (build/ is ignored
// by git; the sheet goes out by e-mail, not into the repo). Import refuses the
// whole file if any row lost a placeholder, then re-runs `flutter gen-l10n`
// by hand is *not* needed -- tool/check.sh regenerates.
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:farmerapp_mobile/translation_pack.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/translations.dart <export|import> [options]',
    );
    exitCode = 2;
    return;
  }
  final root = _workspaceRoot();
  switch (args.first) {
    case 'export':
      _export(root, args.skip(1).toList());
    case 'import':
      _import(root, args.skip(1).toList());
    default:
      stderr.writeln('unknown command "${args.first}" (export | import)');
      exitCode = 2;
  }
}

void _export(Directory root, List<String> args) {
  final locales = _option(args, '--locale') == null
      ? reviewLocales
      : <String>[_option(args, '--locale')!];
  final outDir = Directory(_option(args, '--out') ?? '${root.path}/build/i18n')
    ..createSync(recursive: true);

  final source = readArb(_arb(root, 'en'));
  final keys = source.keys.where((k) => !k.startsWith('@'));
  // One scan for every language: the usage map does not depend on the target.
  final usage = scanUsage(
    <Directory>[
      Directory('${root.path}/apps'),
      Directory('${root.path}/packages/core/lib/src'),
    ],
    keys: keys,
    relativeTo: root.path,
  );

  for (final locale in locales) {
    final file = _arb(root, locale);
    if (!file.existsSync()) {
      stderr.writeln('no ARB for "$locale" (${file.path})');
      exitCode = 1;
      return;
    }
    final rows = buildPack(source: source, target: readArb(file), usage: usage);
    final out = File('${outDir.path}/review_$locale.csv')
      ..writeAsStringSync(toCsv(rows));
    final untranslated = rows.where((r) => r.current.isEmpty).length;
    final noContext = rows.where((r) => r.screens.isEmpty).length;
    print(
      '$locale: ${rows.length} strings -> ${out.path}'
      '${untranslated > 0 ? " ($untranslated untranslated)" : ""}'
      '${noContext > 0 ? ", $noContext with no screen found" : ""}',
    );
  }
  print(
    'Send each sheet to its native speaker. They fill the "reviewed" column '
    '(and "note" for anything they want to argue about); blank means "leave '
    'it as it is".',
  );
}

void _import(Directory root, List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: ... import <reviewed.csv> [--locale xx] [--dry-run]',
    );
    exitCode = 2;
    return;
  }
  final csv = File(positional.first);
  if (!csv.existsSync()) {
    stderr.writeln('no such file: ${csv.path}');
    exitCode = 1;
    return;
  }
  // The locale is in the file name by convention (review_te.csv); --locale
  // overrides it, because a reviewer will rename the file.
  final locale =
      _option(args, '--locale') ??
      RegExp(r'review_([a-z]{2})\.csv$').firstMatch(csv.path)?.group(1);
  if (locale == null) {
    stderr.writeln(
      'cannot tell which language ${csv.path} is: pass --locale <xx>',
    );
    exitCode = 2;
    return;
  }
  final arbFile = _arb(root, locale);
  if (!arbFile.existsSync()) {
    stderr.writeln('no ARB for "$locale" (${arbFile.path})');
    exitCode = 1;
    return;
  }

  final List<ReviewRow> rows;
  try {
    rows = parseCsv(csv.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('cannot read ${csv.path}: ${e.message}');
    exitCode = 1;
    return;
  }

  final result = applyReview(
    target: readArb(arbFile),
    source: readArb(_arb(root, 'en')),
    rows: rows,
  );

  if (!result.ok) {
    stderr.writeln(
      'Refusing to import ${csv.path}: ${result.problems.length} row(s) would '
      'break the app in $locale and nobody else\'s language.',
    );
    result.problems.forEach(stderr.writeln);
    exitCode = 1;
    return;
  }

  if (result.changed.isEmpty) {
    print('$locale: nothing changed (${rows.length} rows read)');
    return;
  }
  if (args.contains('--dry-run')) {
    print('$locale: would update ${result.changed.length} string(s):');
    result.changed.take(20).forEach((k) => print('  $k'));
    return;
  }
  arbFile.writeAsStringSync(writeArb(result.updated));
  print(
    '$locale: updated ${result.changed.length} string(s) in ${arbFile.path}. '
    'Run ./tool/check.sh to regenerate the localisations and the goldens.',
  );
}

File _arb(Directory root, String locale) =>
    File('${root.path}/packages/core/lib/l10n/app_$locale.arb');

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Directory _workspaceRoot() => File.fromUri(Platform.script).parent.parent;
