import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'language_picker.dart';

/// Settings row (A63 / F70) showing the current language; tapping opens a
/// bottom sheet with the [LanguagePicker]. Pure widget: the screen wires
/// [onChanged] to the settings provider.
class LanguageSettingTile extends StatelessWidget {
  /// Creates the tile.
  const LanguageSettingTile({
    required this.value,
    required this.onChanged,
    this.languages = LanguageOption.launchLanguages,
    this.onPlayAudio,
    super.key,
  });

  /// Current language, `null` when the device default is in use.
  final Locale? value;

  /// Called with the newly chosen language.
  final ValueChanged<Locale> onChanged;

  /// Languages offered in the sheet.
  final List<LanguageOption> languages;

  /// Forwarded to [LanguagePicker.onPlayAudio].
  final ValueChanged<Locale>? onPlayAudio;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final current = languages
        .where((o) => o.locale == value)
        .map((o) => o.nativeName)
        .firstOrNull;
    return Material(
      color: app.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: app.borderSide,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const Key('language-setting'),
        minTileHeight: Tokens.sizePrimaryButtonHeight,
        leading: Icon(Icons.language, color: app.palette.primary),
        title: Text(l10n.settingsLanguage, style: app.text.label),
        subtitle: Text(
          current ?? l10n.languagePickerTitle,
          style: app.text.body,
        ),
        trailing: Icon(Icons.chevron_right, color: app.palette.textSecondary),
        onTap: () => _openSheet(context),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final app = sheetContext.app;
        final l10n = CoreLocalizations.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(l10n.languagePickerTitle, style: app.text.title),
                const SizedBox(height: Tokens.space4),
                Flexible(
                  child: SingleChildScrollView(
                    child: LanguagePicker(
                      languages: languages,
                      selected: value,
                      onPlayAudio: onPlayAudio,
                      onSelected: (locale) {
                        Navigator.of(sheetContext).pop();
                        onChanged(locale);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
