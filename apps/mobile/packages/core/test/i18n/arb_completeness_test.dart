import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// FA-004: every key in app_en.arb has a real translation in the other four
/// launch languages, with the same placeholders (checked here in addition to
/// `flutter gen-l10n`'s untranslated-messages report).
void main() {
  const locales = <String>['te', 'kn', 'hi', 'mr'];
  final placeholder = RegExp(r'\{(\w+)\}');

  Map<String, String> messages(String locale) {
    final raw = File('lib/l10n/app_$locale.arb').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, Object?>;
    return <String, String>{
      for (final e in json.entries)
        if (!e.key.startsWith('@')) e.key: e.value! as String,
    };
  }

  final en = messages('en');

  test('app_en.arb is the template and is not empty', () {
    expect(en.length, greaterThan(150));
  });

  for (final locale in locales) {
    test('app_$locale.arb translates every English key', () {
      final other = messages(locale);
      final missing = en.keys.where((k) => !other.containsKey(k)).toList();
      expect(missing, isEmpty, reason: 'missing in app_$locale.arb');
      final extra = other.keys.where((k) => !en.containsKey(k)).toList();
      expect(extra, isEmpty, reason: 'unknown keys in app_$locale.arb');
      for (final e in other.entries) {
        expect(e.value.trim(), isNotEmpty, reason: '${e.key} is empty');
        expect(
          placeholder.allMatches(e.value).map((m) => m.group(1)).toSet(),
          placeholder.allMatches(en[e.key]!).map((m) => m.group(1)).toSet(),
          reason: '${e.key} placeholders differ in $locale',
        );
      }
    });

    test('app_$locale.arb declares its locale', () {
      final raw = File('lib/l10n/app_$locale.arb').readAsStringSync();
      expect((jsonDecode(raw) as Map<String, Object?>)['@@locale'], locale);
    });
  }

  test('script names are the same literal in every ARB', () {
    const native = <String, String>{
      'languageEnglish': 'English',
      'languageTelugu': 'తెలుగు',
      'languageKannada': 'ಕನ್ನಡ',
      'languageHindi': 'हिन्दी',
      'languageMarathi': 'मराठी',
    };
    for (final locale in <String>['en', ...locales]) {
      final m = messages(locale);
      for (final e in native.entries) {
        expect(m[e.key], e.value, reason: '${e.key} in $locale');
      }
    }
  });
}
