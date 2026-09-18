// Fails when user-facing copy is hard-coded instead of coming from the ARB
// files (CLAUDE.md: "Strings go in i18n files, never hard-coded").
//
// The rules live in lib/string_lint.dart (tested by test/string_lint_test.dart).
// Scanned: apps/*/lib/**.dart and packages/core/lib/src/widgets/**.dart.
//
// Usage (from apps/mobile): dart run tool/lint_strings.dart
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:farmerapp_mobile/string_lint.dart';

void main(List<String> args) {
  final root = _workspaceRoot();
  final violations = <StringViolation>[];
  var scanned = 0;
  for (final dir in scanRoots(root)) {
    final result = lintDirectory(dir, relativeTo: root);
    violations.addAll(result.violations);
    scanned += result.scanned;
  }
  if (violations.isNotEmpty) {
    stderr.writeln(
      'Hard-coded user-facing strings found (use ARB/l10n, or $ignoreMarker):',
    );
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
