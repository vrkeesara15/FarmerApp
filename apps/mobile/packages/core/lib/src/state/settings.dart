import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

/// Holds [AppSettings]. Persistence (Drift `kv`) is wired per requirement ID.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  /// Sets the theme.
  void setThemeMode(AppThemeMode mode) {
    state = state.copyWith(themeMode: mode);
  }

  /// Switches Light <-> Sunlight.
  void toggleTheme() {
    setThemeMode(
      state.themeMode == AppThemeMode.light
          ? AppThemeMode.sunlight
          : AppThemeMode.light,
    );
  }

  /// Sets the language.
  void setLocale(Locale locale) {
    state = state.copyWith(locale: locale);
  }
}

/// Settings provider.
final NotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
