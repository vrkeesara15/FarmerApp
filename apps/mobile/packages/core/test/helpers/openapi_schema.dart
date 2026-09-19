import 'dart:io';

/// Property names and `required` list of one `components.schemas` entry.
class OpenApiSchema {
  /// Creates the schema view.
  const OpenApiSchema(this.properties, this.required, {this.closed = false});

  /// Declared property names.
  final Set<String> properties;

  /// Required property names.
  final Set<String> required;

  /// `additionalProperties: false`.
  final bool closed;
}

/// The API contract (`apps/api/openapi.yaml`), read from the monorepo so a
/// schema change on the server breaks the mobile contract test.
final File openApiFile = File('../../../api/openapi.yaml');

/// Reads [name] from `components.schemas` of [openApiFile] (the generated
/// file: schemas at 4 spaces, their keys at 6, property names at 8).
OpenApiSchema openApiSchema(String name) {
  final lines = openApiFile.readAsLinesSync();
  final start = lines.indexOf('    $name:');
  if (start < 0) throw StateError('schema $name not in ${openApiFile.path}');
  final props = <String>{};
  final required = <String>{};
  var closed = false;
  String? section;
  final prop = RegExp(r'^        ([A-Za-z0-9_]+):');
  final item = RegExp(r'^      - ([A-Za-z0-9_]+)$');
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent <= 4) break;
    if (indent == 6 && !line.startsWith('      - ')) {
      section = line.trim().split(':').first;
      if (line.trim() == 'additionalProperties: false') closed = true;
      continue;
    }
    if (section == 'properties') {
      final m = prop.firstMatch(line);
      if (m != null) props.add(m.group(1)!);
    } else if (section == 'required') {
      final m = item.firstMatch(line);
      if (m != null) required.add(m.group(1)!);
    }
  }
  return OpenApiSchema(props, required, closed: closed);
}
