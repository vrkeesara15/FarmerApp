// Fails when a Text widget is given a hard-coded string literal containing
// letters. All user-facing strings must come from the ARB files
// (CLAUDE.md: "Strings go in i18n files, never hard-coded").
//
// Scanned: apps/*/lib/**.dart and packages/core/lib/src/widgets/**.dart.
// Skipped: *.g.dart and generated/ directories.
// Allow a line with a trailing `// i18n-ignore` comment.
//
// Usage (from apps/mobile): dart run tool/lint_strings.dart
//
// ignore_for_file: avoid_print

import 'dart:io';

final RegExp _textLiteral = RegExp(
  r'''\bText\s*\(\s*(?:const\s+)?(['"])((?:(?!\1).)*?)\1''',
  dotAll: true,
);
final RegExp _hasLetters = RegExp(r'\p{L}', unicode: true);
// `${expr}` and `$name` interpolations carry values, not copy.
final RegExp _interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_]\w*');

void main(List<String> args) {
  final root = _workspaceRoot();
  final roots = <Directory>[
    Directory('${root.path}/packages/core/lib/src/widgets'),
    ...Directory('${root.path}/apps')
        .listSync()
        .whereType<Directory>()
        .map((d) => Directory('${d.path}/lib')),
  ];
  final violations = <String>[];
  var scanned = 0;
  for (final dir in roots) {
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') ||
          entity.path.contains('/generated/')) {
        continue;
      }
      scanned++;
      final source = entity.readAsStringSync();
      for (final m in _textLiteral.allMatches(source)) {
        final literal = m.group(2)!;
        final copy = literal.replaceAll(_interpolation, '');
        if (!_hasLetters.hasMatch(copy)) continue;
        final lineStart = source.lastIndexOf('\n', m.start) + 1;
        var lineEnd = source.indexOf('\n', m.end);
        if (lineEnd == -1) lineEnd = source.length;
        final line = source.substring(lineStart, lineEnd);
        if (line.contains('// i18n-ignore')) continue;
        final lineNo = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        final rel = entity.path.substring(root.path.length + 1);
        violations.add(
          '$rel:$lineNo: Text(${m.group(1)}$literal${m.group(1)})',
        );
      }
    }
  }
  if (violations.isNotEmpty) {
    stderr.writeln('Hard-coded user-facing strings found (use ARB/l10n):');
    violations.forEach(stderr.writeln);
    exitCode = 1;
    return;
  }
  print('lint_strings: OK ($scanned files scanned)');
}

Directory _workspaceRoot() {
  // The script lives at <workspace>/tool/lint_strings.dart.
  return File.fromUri(Platform.script).parent.parent;
}
