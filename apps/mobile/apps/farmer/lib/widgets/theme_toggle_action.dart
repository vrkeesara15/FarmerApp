import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App bar action that switches Light <-> Sunlight (F70 setting, exposed
/// early so field testing outdoors is possible).
class ThemeToggleAction extends ConsumerWidget {
  /// Creates the action.
  const ThemeToggleAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final sunlight = mode == AppThemeMode.sunlight;
    return TextButton.icon(
      onPressed: ref.read(settingsProvider.notifier).toggleTheme,
      icon: Icon(sunlight ? Icons.wb_sunny : Icons.wb_sunny_outlined),
      label: Text(sunlight ? l10n.themeSunlight : l10n.themeLight),
    );
  }
}
