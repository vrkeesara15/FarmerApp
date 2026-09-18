// Generates lib/src/tokens/tokens.g.dart from design/tokens.json.
//
// Usage (from apps/mobile/packages/core):
//   dart run tool/gen_tokens.dart
//
// The script is idempotent: re-running it on the same tokens.json produces
// byte-identical output. It reads the W3C Design Tokens file, resolves alias
// references such as `{color.status.success}` per theme, and emits Dart
// constants. Nothing in lib/ may hard-code colours or sizes; widgets consume
// these constants through the theme layer.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const String tokensPath = '../../../../design/tokens.json';
const String outputPath = 'lib/src/tokens/tokens.g.dart';
const List<String> themes = <String>['light', 'sunlight', 'dark'];

void main(List<String> args) {
  final scriptDir = File.fromUri(Platform.script).parent;
  final packageDir = scriptDir.parent;
  final tokensFile = File.fromUri(packageDir.uri.resolve(tokensPath));
  if (!tokensFile.existsSync()) {
    stderr.writeln('tokens.json not found at ${tokensFile.path}');
    exitCode = 2;
    return;
  }
  final json =
      jsonDecode(tokensFile.readAsStringSync()) as Map<String, dynamic>;
  final out = File.fromUri(packageDir.uri.resolve(outputPath));
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(_generate(json));
  final fmt = Process.runSync('dart', <String>['format', out.path]);
  if (fmt.exitCode != 0) {
    stderr.writeln(fmt.stderr);
    exitCode = fmt.exitCode;
    return;
  }
  print('Wrote ${out.path}');
}

// ---------------------------------------------------------------------------
// Colour helpers
// ---------------------------------------------------------------------------

/// Flattened colour token: `path` like `status.success`, value per theme.
class _ColorToken {
  _ColorToken(this.path, this.byTheme, this.description);
  final List<String> path;
  final Map<String, String> byTheme; // theme -> hex or alias
  final String? description;

  String get fieldName {
    final parts = path.where((p) => p != 'default').toList();
    return _camel(parts);
  }
}

String _camel(List<String> parts) {
  final b = StringBuffer(parts.first);
  for (final p in parts.skip(1)) {
    b.write(p[0].toUpperCase());
    b.write(p.substring(1));
  }
  return b.toString();
}

void _collectColors(
  Map<String, dynamic> node,
  List<String> path,
  List<_ColorToken> out,
) {
  if (node.containsKey(r'$type') && node[r'$type'] == 'color') {
    final value = node[r'$value'] as String;
    final ext = node[r'$extensions'] as Map<String, dynamic>?;
    final themeMap =
        (ext?['theme'] as Map<String, dynamic>?)?.cast<String, String>() ??
        <String, String>{};
    final byTheme = <String, String>{'light': value};
    for (final t in themes.skip(1)) {
      byTheme[t] = themeMap[t] ?? value;
    }
    out.add(_ColorToken(path, byTheme, node[r'$description'] as String?));
    return;
  }
  for (final entry in node.entries) {
    if (entry.key.startsWith(r'$')) continue;
    if (entry.value is Map<String, dynamic>) {
      _collectColors(entry.value as Map<String, dynamic>, <String>[
        ...path,
        entry.key,
      ], out);
    }
  }
}

String _resolve(String value, String theme, Map<String, _ColorToken> byPath) {
  var v = value;
  var guard = 0;
  while (v.startsWith('{')) {
    final ref = v.substring(1, v.length - 1); // color.status.success
    final key = ref.split('.').skip(1).join('.');
    final target = byPath[key];
    if (target == null) {
      throw StateError('Unresolved token alias $value');
    }
    v = target.byTheme[theme]!;
    if (++guard > 10) throw StateError('Alias loop at $value');
  }
  return v;
}

String _dartColor(String hex) {
  var h = hex.replaceFirst('#', '').toUpperCase();
  if (h.length == 6) h = 'FF$h';
  if (h.length == 8) {
    // tokens.json uses RRGGBBAA; Dart wants AARRGGBB.
    if (hex.length == 9) h = '${h.substring(6)}${h.substring(0, 6)}';
  }
  return 'Color(0x$h)';
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

String _generate(Map<String, dynamic> json) {
  final colors = <_ColorToken>[];
  _collectColors(json['color'] as Map<String, dynamic>, <String>[], colors);
  final byPath = <String, _ColorToken>{
    for (final c in colors) c.path.join('.'): c,
  };

  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln(
      '// Source: design/tokens.json. Regenerate with '
      '`dart run tool/gen_tokens.dart`.',
    )
    ..writeln('// ignore_for_file: public_member_api_docs')
    ..writeln()
    ..writeln("import 'dart:ui';")
    ..writeln();

  // Palette class.
  b.writeln(
    '/// Semantic colour palette for one theme (see design/tokens.json).',
  );
  b.writeln('class TokenPalette {');
  b.writeln('  const TokenPalette({');
  for (final c in colors) {
    b.writeln('    required this.${c.fieldName},');
  }
  b.writeln('  });');
  b.writeln();
  for (final c in colors) {
    if (c.description != null) b.writeln('  /// ${c.description}');
    b.writeln('  final Color ${c.fieldName};');
  }
  b.writeln('}');
  b.writeln();

  b.writeln('/// A text style token from the mobile type scale (sizes in sp).');
  b.writeln('class TokenTextStyle {');
  b.writeln(
    '  const TokenTextStyle({required this.fontSize, '
    'required this.lineHeight, required this.fontWeight});',
  );
  b.writeln('  final double fontSize;');
  b.writeln('  final double lineHeight;');
  b.writeln('  /// 400 or 600 only.');
  b.writeln('  final int fontWeight;');
  b.writeln('}');
  b.writeln();

  b.writeln('/// Shadow token (only bottom sheets and FAB use it).');
  b.writeln('class TokenShadow {');
  b.writeln(
    '  const TokenShadow({required this.offsetX, required this.offsetY, '
    'required this.blur, required this.spread, required this.color});',
  );
  b.writeln('  final double offsetX;');
  b.writeln('  final double offsetY;');
  b.writeln('  final double blur;');
  b.writeln('  final double spread;');
  b.writeln('  final Color color;');
  b.writeln('}');
  b.writeln();

  b.writeln('/// All design tokens. Themes: light (default), sunlight, dark.');
  b.writeln('abstract final class Tokens {');
  for (final t in themes) {
    b.writeln('  static const TokenPalette $t = TokenPalette(');
    for (final c in colors) {
      final hex = _resolve(c.byTheme[t]!, t, byPath);
      b.writeln('    ${c.fieldName}: ${_dartColor(hex)},');
    }
    b.writeln('  );');
    b.writeln();
  }

  // Fonts.
  final font = json['font'] as Map<String, dynamic>;
  final families = font['family'] as Map<String, dynamic>;
  for (final f in families.entries) {
    final list = (f.value as Map<String, dynamic>)[r'$value'] as List<dynamic>;
    final items = list.map((e) => "'$e'").join(', ');
    b.writeln(
      '  static const List<String> fontFamily'
      '${_cap(f.key)} = <String>[$items];',
    );
  }
  final weights = font['weight'] as Map<String, dynamic>;
  for (final w in weights.entries) {
    b.writeln(
      '  static const int fontWeight${_cap(w.key)} = '
      '${(w.value as Map<String, dynamic>)[r'$value']};',
    );
  }
  final features = font['features'] as Map<String, dynamic>;
  b.writeln("  static const String fontFeatures = '${features[r'$value']}';");
  b.writeln();

  // Type scale (mobile only; console scale is for the web).
  final mobile =
      (json['text'] as Map<String, dynamic>)['mobile'] as Map<String, dynamic>;
  for (final s in mobile.entries) {
    final node = s.value as Map<String, dynamic>;
    if (node[r'$type'] == 'typography') {
      final v = node[r'$value'] as Map<String, dynamic>;
      b.writeln(
        '  static const TokenTextStyle text${_cap(s.key)} = TokenTextStyle('
        'fontSize: ${_num(v['fontSize'])}, '
        'lineHeight: ${_num(v['lineHeight'])}, '
        'fontWeight: ${v['fontWeight']});',
      );
    } else if (node[r'$type'] == 'number') {
      b.writeln('  static const double ${s.key} = ${node[r'$value']};');
    }
  }
  b.writeln();

  // Dimensions: space, radius, size.
  for (final group in <String>['space', 'radius', 'size']) {
    final map = json[group] as Map<String, dynamic>;
    for (final e in map.entries) {
      final v = (e.value as Map<String, dynamic>)[r'$value'];
      b.writeln('  static const double $group${_cap(e.key)} = ${_num(v)};');
    }
    b.writeln();
  }

  // Border width per theme.
  final bw =
      (json['border'] as Map<String, dynamic>)['width'] as Map<String, dynamic>;
  final bwExt =
      ((bw[r'$extensions'] as Map<String, dynamic>?)?['theme']
          as Map<String, dynamic>?) ??
      <String, dynamic>{};
  for (final t in themes) {
    final v = bwExt[t] ?? bw[r'$value'];
    b.writeln('  static const double borderWidth${_cap(t)} = ${_num(v)};');
  }
  b.writeln();

  // Elevation.
  final elev = json['elevation'] as Map<String, dynamic>;
  for (final e in elev.entries) {
    final v = (e.value as Map<String, dynamic>)[r'$value'];
    if (v is Map<String, dynamic>) {
      b.writeln(
        '  static const TokenShadow elevation${_cap(e.key)} = TokenShadow('
        'offsetX: ${_num(v['offsetX'])}, offsetY: ${_num(v['offsetY'])}, '
        'blur: ${_num(v['blur'])}, spread: ${_num(v['spread'])}, '
        'color: ${_dartColor(v['color'] as String)});',
      );
    } else {
      b.writeln('  static const TokenShadow? elevation${_cap(e.key)} = null;');
    }
  }
  b.writeln('}');
  return b.toString();
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

String _num(Object? raw) {
  final s = raw.toString().replaceAll(RegExp('[a-z]+'), '');
  final d = double.parse(s);
  return d == d.roundToDouble() ? '${d.toInt()}' : '$d';
}
