import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// One selectable language.
@immutable
class LanguageOption {
  /// Creates an option.
  const LanguageOption({required this.locale, required this.nativeName});

  /// The locale selected when tapped.
  final Locale locale;

  /// Name written in its own script, e.g. `తెలుగు`.
  final String nativeName;

  /// The five launch languages (NF-008).
  static const List<LanguageOption> launchLanguages = <LanguageOption>[
    LanguageOption(locale: Locale('te'), nativeName: 'తెలుగు'),
    LanguageOption(locale: Locale('kn'), nativeName: 'ಕನ್ನಡ'),
    LanguageOption(locale: Locale('hi'), nativeName: 'हिन्दी'),
    LanguageOption(locale: Locale('mr'), nativeName: 'मराठी'),
    LanguageOption(locale: Locale('en'), nativeName: 'English'),
  ];
}

/// Large language tiles with the script name and an audio play button
/// (SPEC 13.1 `LanguagePicker`).
class LanguagePicker extends StatelessWidget {
  /// Creates the picker.
  const LanguagePicker({
    required this.onSelected,
    this.languages = LanguageOption.launchLanguages,
    this.selected,
    this.onPlayAudio,
    super.key,
  });

  /// Languages to offer.
  final List<LanguageOption> languages;

  /// Currently selected locale, if any.
  final Locale? selected;

  /// Called when a tile is tapped.
  final ValueChanged<Locale> onSelected;

  /// Called when the speaker button is tapped; hidden when `null`.
  final ValueChanged<Locale>? onPlayAudio;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Tokens.space3,
        crossAxisSpacing: Tokens.space3,
        mainAxisExtent: 128,
      ),
      itemCount: languages.length,
      itemBuilder: (context, index) {
        final option = languages[index];
        return _LanguageTile(
          option: option,
          englishName: _englishName(l10n, option.locale),
          selected: option.locale == selected,
          onTap: () => onSelected(option.locale),
          onPlay: onPlayAudio == null
              ? null
              : () => onPlayAudio!(option.locale),
        );
      },
    );
  }

  static String _englishName(CoreLocalizations l10n, Locale locale) {
    return switch (locale.languageCode) {
      'te' => l10n.languageTeluguName,
      'kn' => l10n.languageKannadaName,
      'hi' => l10n.languageHindiName,
      'mr' => l10n.languageMarathiName,
      _ => l10n.languageEnglishName,
    };
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.option,
    required this.englishName,
    required this.selected,
    required this.onTap,
    required this.onPlay,
  });

  final LanguageOption option;
  final String englishName;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final borderColor = selected ? p.primary : p.border;
    final width = selected ? app.borderWidth + 1 : app.borderWidth;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.nativeName}, $englishName',
      child: Material(
        color: selected ? app.tint(p.primaryContainer) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: BorderSide(color: borderColor, width: width),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (selected)
                      Icon(Icons.check_circle, color: p.primary)
                    else
                      Icon(Icons.translate, color: p.textSecondary),
                    const Spacer(),
                    if (onPlay != null)
                      Semantics(
                        button: true,
                        label: '${l10n.languagePlayAudio} ${option.nativeName}',
                        child: SizedBox.square(
                          dimension: Tokens.sizeTouchTargetMin,
                          child: IconButton(
                            onPressed: onPlay,
                            color: p.primary,
                            tooltip: l10n.languagePlayAudio,
                            icon: const Icon(Icons.volume_up_outlined),
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  option.nativeName,
                  style: app.text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  englishName,
                  style: app.text.caption.copyWith(color: p.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
