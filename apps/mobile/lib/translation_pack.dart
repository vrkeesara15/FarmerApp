/// NF-008 translation review pack: turn the ARB files into something a native
/// speaker can actually review, and turn their answer back into ARB.
///
/// NF-008 ends with "all farmer-facing text reviewed by a native speaker".
/// That is a human gate, and it was blocked on a practical problem: a reviewer
/// who is a Telugu-speaking agronomist, not an engineer, cannot be handed five
/// 2,000-line JSON files. This library is the two halves of the loop:
///
/// * [buildPack] produces one row per string per language, carrying the
///   English source, the current translation, the ARB description, the
///   placeholders that must survive, and **where the string appears** -- the
///   screens that use it, found by scanning the Dart sources for `l10n.<key>`.
///   Context is the whole point: "Done" on a payment screen and "Done" on a
///   photo screen are different words in Telugu.
/// * [applyReview] reads the returned rows back, checks that every placeholder
///   is still present and that nothing was silently dropped, and returns the
///   updated ARB content with key order and metadata untouched.
///
/// `tool/translations.dart` is the command-line wrapper; this library holds
/// the logic so `test/translation_pack_test.dart` can test it without files.
library;

import 'dart:convert';
import 'dart:io';

/// The five launch languages (NF-008). English is the source, not a target.
const List<String> reviewLocales = <String>['te', 'kn', 'hi', 'mr'];

/// Columns of the review CSV, in order.
const List<String> reviewColumns = <String>[
  'key',
  'screens',
  'description',
  'placeholders',
  'english',
  'current',
  'reviewed',
  'note',
];

/// One string, in one language, ready for review.
class ReviewRow {
  /// Creates the row.
  const ReviewRow({
    required this.key,
    required this.english,
    required this.current,
    this.screens = const <String>[],
    this.description = '',
    this.placeholders = const <String>[],
    this.reviewed = '',
    this.note = '',
  });

  /// ARB key.
  final String key;

  /// The English source string.
  final String english;

  /// The translation as it stands today.
  final String current;

  /// Where the string is shown, most specific first.
  final List<String> screens;

  /// The ARB `description`, when the key has one.
  final String description;

  /// Placeholder names that must appear in the reviewed string.
  final List<String> placeholders;

  /// What the reviewer wrote back (empty on export).
  final String reviewed;

  /// The reviewer's comment.
  final String note;

  /// The row as CSV cells, in [reviewColumns] order.
  List<String> get cells => <String>[
    key,
    screens.join(' | '),
    description,
    placeholders.join(' '),
    english,
    current,
    reviewed,
    note,
  ];
}

/// Placeholder names used by an ICU/ARB message: `{count}`, `{acres}`.
///
/// Plural and select bodies name the same placeholder at the front
/// (`{count, plural, ...}`), so the set is what matters, not the order.
List<String> placeholdersOf(String message) {
  final names = <String>{};
  for (final match in RegExp(
    r'\{\s*([a-zA-Z_][a-zA-Z0-9_]*)',
  ).allMatches(message)) {
    names.add(match.group(1)!);
  }
  return names.toList()..sort();
}

/// Builds the review rows for one language.
///
/// [source] and [target] are parsed ARB maps; [usage] maps an ARB key to the
/// places it is used (see [scanUsage]). Keys starting with `@` are ARB
/// metadata, and `@@locale` is the file's own header: neither is a string
/// anybody reads.
List<ReviewRow> buildPack({
  required Map<String, Object?> source,
  required Map<String, Object?> target,
  Map<String, List<String>> usage = const <String, List<String>>{},
}) {
  final rows = <ReviewRow>[];
  for (final entry in source.entries) {
    final key = entry.key;
    if (key.startsWith('@')) continue;
    final english = '${entry.value}';
    final meta = source['@$key'];
    final description = meta is Map && meta['description'] != null
        ? '${meta['description']}'
        : '';
    rows.add(
      ReviewRow(
        key: key,
        english: english,
        current: target[key] == null ? '' : '${target[key]}',
        screens: usage[key] ?? const <String>[],
        description: description,
        placeholders: placeholdersOf(english),
      ),
    );
  }
  return rows;
}

/// What [applyReview] did, or refused to do.
class ReviewResult {
  /// Creates the result.
  const ReviewResult({
    required this.updated,
    required this.changed,
    required this.problems,
  });

  /// The ARB map after the review (unchanged when [problems] is not empty).
  final Map<String, Object?> updated;

  /// Keys whose translation the reviewer changed.
  final List<String> changed;

  /// Why a row was refused. A non-empty list means nothing was written.
  final List<String> problems;

  /// Whether the review can be applied.
  bool get ok => problems.isEmpty;
}

/// Applies reviewed rows to an ARB map.
///
/// Refuses the whole file, rather than part of it, when a row would break the
/// app: a dropped placeholder is a runtime crash in the farmer's language and
/// nobody else's, which is exactly the bug that survives to production. Rows
/// with an empty `reviewed` cell are left alone -- a reviewer working through
/// 2,000 strings over a week sends back a partly filled sheet, and that has to
/// be normal.
ReviewResult applyReview({
  required Map<String, Object?> target,
  required Map<String, Object?> source,
  required List<ReviewRow> rows,
}) {
  final updated = Map<String, Object?>.of(target);
  final changed = <String>[];
  final problems = <String>[];

  for (final row in rows) {
    final reviewed = row.reviewed.trim();
    if (reviewed.isEmpty) continue;
    if (!source.containsKey(row.key)) {
      problems.add('${row.key}: not an ARB key (renamed or misspelt?)');
      continue;
    }
    final expected = placeholdersOf('${source[row.key]}');
    final got = placeholdersOf(reviewed);
    final missing = expected.where((p) => !got.contains(p)).toList();
    final extra = got.where((p) => !expected.contains(p)).toList();
    if (missing.isNotEmpty) {
      problems.add('${row.key}: lost placeholder(s) ${missing.join(", ")}');
      continue;
    }
    if (extra.isNotEmpty) {
      problems.add('${row.key}: unknown placeholder(s) ${extra.join(", ")}');
      continue;
    }
    if (reviewed == updated[row.key]) continue;
    updated[row.key] = reviewed;
    changed.add(row.key);
  }

  return ReviewResult(
    updated: problems.isEmpty ? updated : target,
    changed: problems.isEmpty ? changed : const <String>[],
    problems: problems,
  );
}

// --------------------------------------------------------------------------- CSV

/// Renders rows as RFC 4180 CSV with a header.
///
/// Excel and Google Sheets are what a reviewer will open this in, so the file
/// starts with a UTF-8 BOM: without it Excel on Windows renders Telugu as
/// mojibake and the reviewer "fixes" text that was never broken.
String toCsv(List<ReviewRow> rows) {
  final buffer = StringBuffer('﻿')
    ..writeln(reviewColumns.map(_csvCell).join(','));
  for (final row in rows) {
    buffer.writeln(row.cells.map(_csvCell).join(','));
  }
  return buffer.toString();
}

String _csvCell(String value) {
  final needsQuotes =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  final escaped = value.replaceAll('"', '""');
  return needsQuotes ? '"$escaped"' : escaped;
}

/// Parses the CSV a reviewer sends back.
///
/// Tolerates the BOM, CRLF line endings and columns moved around (the header
/// names the order), because every one of those happens once a sheet has been
/// through Excel.
List<ReviewRow> parseCsv(String csv) {
  final table = _parseCsvTable(csv.startsWith('﻿') ? csv.substring(1) : csv);
  if (table.isEmpty) return <ReviewRow>[];
  final header = table.first.map((h) => h.trim().toLowerCase()).toList();
  int index(String name) => header.indexOf(name);
  String cell(List<String> row, String name) {
    final i = index(name);
    return i >= 0 && i < row.length ? row[i] : '';
  }

  if (index('key') < 0) {
    throw const FormatException('the CSV has no "key" column');
  }

  return <ReviewRow>[
    for (final row in table.skip(1))
      if (cell(row, 'key').trim().isNotEmpty)
        ReviewRow(
          key: cell(row, 'key').trim(),
          english: cell(row, 'english'),
          current: cell(row, 'current'),
          reviewed: cell(row, 'reviewed'),
          note: cell(row, 'note'),
        ),
  ];
}

List<List<String>> _parseCsvTable(String csv) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var i = 0;
  var sawAnything = false;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    rows.add(row);
    row = <String>[];
  }

  while (i < csv.length) {
    final ch = csv[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < csv.length && csv[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        quoted = false;
        i++;
        continue;
      }
      cell.write(ch);
      i++;
      continue;
    }
    switch (ch) {
      case '"':
        quoted = true;
        sawAnything = true;
        i++;
      case ',':
        endCell();
        sawAnything = true;
        i++;
      case '\r':
        i++;
      case '\n':
        endRow();
        sawAnything = false;
        i++;
      default:
        cell.write(ch);
        sawAnything = true;
        i++;
    }
  }
  if (sawAnything || cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

// --------------------------------------------------------------------------- usage

/// Finds where each ARB key is used, so the reviewer sees context.
///
/// Matches `l10n.<key>`, `l10n.<key>(`, `localizations.<key>` and the
/// generated accessor on any receiver -- the apps all read strings through one
/// of those. A key with no hit is reported with no screens rather than
/// dropped: it may be new, or dead, and the reviewer is not the right person
/// to decide which.
Map<String, List<String>> scanUsage(
  Iterable<Directory> roots, {
  required Iterable<String> keys,
  required String relativeTo,
}) {
  final byKey = <String, Set<String>>{for (final key in keys) key: <String>{}};
  final pattern = RegExp(
    r'\b(?:l10n|localizations|t)\.([a-zA-Z_][a-zA-Z0-9_]*)',
  );
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.contains('/generated/') || file.path.endsWith('.g.dart')) {
        continue;
      }
      final text = file.readAsStringSync();
      final where = _screenOf(file.path, relativeTo);
      for (final match in pattern.allMatches(text)) {
        final key = match.group(1)!;
        byKey[key]?.add(where);
      }
    }
  }
  return <String, List<String>>{
    for (final entry in byKey.entries) entry.key: entry.value.toList()..sort(),
  };
}

/// A human-readable "where" for a source file: `farmer/advisory/add_crop`.
String _screenOf(String path, String relativeTo) {
  var rel = path.startsWith(relativeTo)
      ? path.substring(relativeTo.length)
      : path;
  rel = rel.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
  rel = rel
      .replaceFirst('apps/', '')
      .replaceFirst('packages/core/lib/src/', 'core/')
      .replaceFirst('/lib/screens/', '/')
      .replaceFirst('/lib/widgets/', '/widgets/')
      .replaceFirst('/lib/', '/');
  return rel.replaceFirst(RegExp(r'\.dart$'), '').replaceAll('_screen', '');
}

// --------------------------------------------------------------------------- ARB I/O

/// Reads an ARB file as an ordered map.
Map<String, Object?> readArb(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

/// Writes an ARB map back with the project's formatting (2-space indent,
/// trailing newline), so a review lands as a small diff instead of a rewrite.
String writeArb(Map<String, Object?> arb) =>
    '${const JsonEncoder.withIndent('  ').convert(arb)}\n';
