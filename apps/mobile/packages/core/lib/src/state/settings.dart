import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../db/app_database.dart';
import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';

/// User-facing settings shared by both apps (A63 / F70).
@immutable
class AppSettings {
  /// Creates settings.
  const AppSettings({this.themeMode = AppThemeMode.light, this.locale});

  /// Light or Sunlight.
  final AppThemeMode themeMode;

  /// Chosen language; `null` until the user picks one (falls back to device).
  final Locale? locale;

  /// Copy with overrides.
  AppSettings copyWith({AppThemeMode? themeMode, Locale? locale}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(themeMode, locale);
}

/// Persists [AppSettings] across app starts (FA-004: language survives a
/// restart; A63/F70 theme likewise).
abstract interface class SettingsStore {
  /// Reads the stored settings, defaults when nothing is stored.
  Future<AppSettings> load();

  /// Replaces the stored settings.
  Future<void> save(AppSettings settings);
}

/// Volatile store for tests and previews.
class InMemorySettingsStore implements SettingsStore {
  /// Creates the store with an optional initial value.
  InMemorySettingsStore([this._value = const AppSettings()]);

  AppSettings _value;

  @override
  Future<AppSettings> load() async => _value;

  @override
  Future<void> save(AppSettings settings) async => _value = settings;
}

/// Store backed by the Drift `kv` table of [AppDatabase].
class KvSettingsStore implements SettingsStore {
  /// Creates the store over [db].
  KvSettingsStore(this.db);

  /// The database (in-memory in tests, a file on device).
  final AppDatabase db;

  /// `kv.key` for the language code.
  static const String localeKey = 'settings.locale';

  /// `kv.key` for the theme (`light` | `sunlight`).
  static const String themeKey = 'settings.theme_mode';

  @override
  Future<AppSettings> load() async {
    final code = await db.getValue(localeKey);
    final theme = await db.getValue(themeKey);
    return AppSettings(
      locale: parseSupportedLocale(code),
      themeMode: AppThemeMode.values.firstWhere(
        (m) => m.name == theme,
        orElse: () => AppThemeMode.light,
      ),
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final locale = settings.locale;
    if (locale == null) {
      await db.removeValue(localeKey);
    } else {
      await db.setValue(localeKey, locale.toLanguageTag());
    }
    await db.setValue(themeKey, settings.themeMode.name);
  }
}

/// Parses a stored language tag into one of [CoreLocalizations.supportedLocales],
/// or `null` when missing or unsupported (e.g. after a language is removed).
Locale? parseSupportedLocale(String? tag) {
  if (tag == null || tag.isEmpty) return null;
  final code = tag.split(RegExp('[-_]')).first.toLowerCase();
  for (final locale in CoreLocalizations.supportedLocales) {
    if (locale.languageCode == code) return locale;
  }
  return null;
}

/// The settings store; the apps override it with a [KvSettingsStore].
final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (ref) => InMemorySettingsStore(),
);

/// Settings loaded before the first frame; see [settingsOverrides].
final Provider<AppSettings> initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

/// Loads the persisted settings from [store] and returns the overrides the
/// apps pass to their root `ProviderScope` so the first frame already uses
/// the saved language and theme (no flash, no restart needed).
Future<List<Override>> settingsOverrides(SettingsStore store) async {
  final initial = await store.load();
  return <Override>[
    settingsStoreProvider.overrideWithValue(store),
    initialSettingsProvider.overrideWithValue(initial),
  ];
}

/// Holds [AppSettings] and writes every change to [settingsStoreProvider].
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  void _update(AppSettings next) {
    if (next == state) return;
    state = next;
    unawaited(ref.read(settingsStoreProvider).save(next));
  }

  /// Sets the theme.
  void setThemeMode(AppThemeMode mode) {
    _update(state.copyWith(themeMode: mode));
  }

  /// Switches Light <-> Sunlight.
  void toggleTheme() {
    setThemeMode(
      state.themeMode == AppThemeMode.light
          ? AppThemeMode.sunlight
          : AppThemeMode.light,
    );
  }

  /// Sets the language. `MaterialApp.locale` watches this, so every screen
  /// re-localises immediately (FA-004: switch without restart).
  void setLocale(Locale locale) {
    _update(state.copyWith(locale: locale));
  }
}

/// Settings provider.
final NotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
