/// Hard-coded UI string lint for the mobile workspace (FA-004).
///
/// All user-facing copy must come from the ARB files
/// (CLAUDE.md: "Strings go in i18n files, never hard-coded"). This library
/// finds string literals that reach the screen and is exercised both by
/// `tool/lint_strings.dart` (CI) and by `test/string_lint_test.dart`.
///
/// Flagged:
///   * `Text('Hello')`, `Text("Hi")`, `const Text('x')`
///   * named arguments that render text on the design-system widgets and on
///     Material widgets: `label:`, `tooltip:`, `hintText:`, `helperText:`,
///     `errorText:`, `labelText:`, `semanticsLabel:`, `semanticLabel:`
///     (see [textArguments]).
///
/// Allowed:
///   * literals without letters (`'+91'`, `'—'`, `'12:30'`);
///   * literals that are only interpolations (`'$a, $b'`);
///   * a `// i18n-ignore` comment on the same or the previous line;
///   * `// i18n-ignore-file` anywhere in the first 10 lines of a file;
///   * generated code (`*.g.dart`, `generated/`) and the paths in
///     [allowPathFragments].
library;

import 'dart:io';

/// Named arguments whose string-literal value is shown to the user.
const Set<String> textArguments = <String>{
  'label',
  'tooltip',
  'hintText',
  'helperText',
  'errorText',
  'labelText',
  'semanticsLabel',
  'semanticLabel',
};

/// Path fragments that are never linted (generated or non-UI code).
const List<String> allowPathFragments = <String>[
  '.g.dart',
  '/generated/',
  '/build/',
  '/.dart_tool/',
];

/// Marker that silences the current (or next) line.
const String ignoreMarker = '// i18n-ignore';

/// Marker that silences a whole file (must appear in the first 10 lines).
const String ignoreFileMarker = '// i18n-ignore-file';

final RegExp _textLiteral = RegExp(
  r'''\bText\s*\(\s*(?:const\s+)?(['"])((?:(?!\1).)*?)\1''',
  dotAll: true,
);
final RegExp _argLiteral = RegExp(
  '\\b(${textArguments.join('|')})\\s*:\\s*(?:const\\s+)?([\'"])((?:(?!\\2).)*?)\\2',
  dotAll: true,
);
final RegExp _hasLetters = RegExp(r'\p{L}', unicode: true);
// `${expr}` and `$name` interpolations carry values, not copy.
final RegExp _interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_]\w*');

/// One hard-coded string found by the lint.
class StringViolation {
  /// Creates a violation.
  const StringViolation({
    required this.path,
    required this.line,
    required this.kind,
    required this.literal,
  });

  /// File path as given to the linter.
  final String path;

  /// 1-based line number of the literal.
  final int line;

  /// `Text` or the named argument (`label`, `tooltip`, ...).
  final String kind;

  /// The literal's content without quotes.
  final String literal;

  @override
  String toString() => "$path:$line: $kind('$literal')";
}

/// Whether [path] is subject to the lint.
bool isLinted(String path) {
  if (!path.endsWith('.dart')) return false;
  return !allowPathFragments.any(path.contains);
}

/// Lints Dart [source] and returns every hard-coded user-facing literal.
List<StringViolation> lintSource(String source, {String path = '<memory>'}) {
  final head = source.split('\n').take(10).join('\n');
  if (head.contains(ignoreFileMarker)) return const <StringViolation>[];

  final found = <StringViolation>[];
  void consider(RegExpMatch m, String kind, String literal) {
    final copy = literal.replaceAll(_interpolation, '');
    if (!_hasLetters.hasMatch(copy)) return;
    final lineStart = source.lastIndexOf('\n', m.start) + 1;
    var lineEnd = source.indexOf('\n', m.end);
    if (lineEnd == -1) lineEnd = source.length;
    final line = source.substring(lineStart, lineEnd);
    if (line.contains(ignoreMarker)) return;
    if (lineStart > 0) {
      final prevStart = source.lastIndexOf('\n', lineStart - 2) + 1;
      final prev = source.substring(prevStart, lineStart - 1);
      if (prev.trim().startsWith(ignoreMarker)) return;
    }
    final lineNo = '\n'.allMatches(source.substring(0, m.start)).length + 1;
    found.add(
      StringViolation(path: path, line: lineNo, kind: kind, literal: literal),
    );
  }

  for (final m in _textLiteral.allMatches(source)) {
    consider(m, 'Text', m.group(2)!);
  }
  for (final m in _argLiteral.allMatches(source)) {
    consider(m, m.group(1)!, m.group(3)!);
  }
  found.sort((a, b) => a.line.compareTo(b.line));
  return found;
}

/// Lints every `.dart` file under [dir] (recursively) that [isLinted].
///
/// Paths in the result are relative to [relativeTo] when given.
({List<StringViolation> violations, int scanned}) lintDirectory(
  Directory dir, {
  Directory? relativeTo,
}) {
  final violations = <StringViolation>[];
  var scanned = 0;
  if (!dir.existsSync()) return (violations: violations, scanned: 0);
  final entries = dir.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in entries) {
    if (!isLinted(file.path)) continue;
    scanned++;
    var shown = file.path;
    if (relativeTo != null && shown.startsWith(relativeTo.path)) {
      shown = shown.substring(relativeTo.path.length + 1);
    }
    violations.addAll(lintSource(file.readAsStringSync(), path: shown));
  }
  return (violations: violations, scanned: scanned);
}

/// The directories linted in CI for a workspace rooted at [workspace]:
/// `packages/core/lib/src/widgets` and `apps/*/lib`.
List<Directory> scanRoots(Directory workspace) {
  final apps = Directory('${workspace.path}/apps');
  final appDirs = apps.existsSync()
      ? (apps.listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      : const <Directory>[];
  return <Directory>[
    Directory('${workspace.path}/packages/core/lib/src/widgets'),
    for (final d in appDirs) Directory('${d.path}/lib'),
  ];
}
