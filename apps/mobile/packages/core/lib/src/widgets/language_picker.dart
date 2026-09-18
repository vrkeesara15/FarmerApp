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
///
/// Each tile is fully in its own language (script name + "Listen" label) so
/// a user who cannot read the current UI language can still find theirs;
/// only the small caption (English name) follows the current locale.
class LanguagePicker extends StatelessWidget {
  /// Creates the picker.
  const LanguagePicker({
    required this.onSelected,
    this.languages = LanguageOption.launchLanguages,
    this.selected,
    this.onPlayAudio,
    super.key,
  }) : compact = false,
       keyPrefix = null;

  /// Compact variant for forms (A21a "preferred language"): one row of
  /// selectable chips with the script names, no audio button.
  const LanguagePicker.compact({
    required this.onSelected,
    this.languages = LanguageOption.launchLanguages,
    this.selected,
    this.keyPrefix,
    super.key,
  }) : compact = true,
       onPlayAudio = null;

  /// Chips instead of tiles.
  final bool compact;

  /// Compact chips get `Key('<keyPrefix><languageCode>')` (tests).
  final String? keyPrefix;

  /// Languages to offer.
  final List<LanguageOption> languages;

  /// Currently selected locale, if any.
  final Locale? selected;

  /// Called when a tile is tapped.
  final ValueChanged<Locale> onSelected;

  /// Called when the speaker button is tapped; hidden when `null`.
  final ValueChanged<Locale>? onPlayAudio;

  /// Tile height: script name, caption and a 48 dp "Listen" row.
  static const double tileExtent = 144;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    if (compact) {
      return Wrap(
        spacing: Tokens.space2,
        runSpacing: Tokens.space2,
        children: <Widget>[
          for (final option in languages)
            _LanguageChip(
              key: keyPrefix == null
                  ? null
                  : Key('$keyPrefix${option.locale.languageCode}'),
              option: option,
              englishName: _englishName(l10n, option.locale),
              selected: option.locale == selected,
              onTap: () => onSelected(option.locale),
            ),
        ],
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Tokens.space3,
        crossAxisSpacing: Tokens.space3,
        mainAxisExtent: tileExtent,
      ),
      itemCount: languages.length,
      itemBuilder: (context, index) {
        final option = languages[index];
        return _LanguageTile(
          option: option,
          englishName: _englishName(l10n, option.locale),
          listenLabel: _ownLocalizations(option.locale, l10n).languagePlayAudio,
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

  /// Strings in the tile's own language; [fallback] for unsupported locales.
  static CoreLocalizations _ownLocalizations(
    Locale locale,
    CoreLocalizations fallback,
  ) {
    try {
      return lookupCoreLocalizations(locale);
    } on FlutterError {
      return fallback;
    }
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.option,
    required this.englishName,
    required this.listenLabel,
    required this.selected,
    required this.onTap,
    required this.onPlay,
  });

  final LanguageOption option;
  final String englishName;
  final String listenLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final borderColor = selected ? p.primary : p.border;
    final width = selected ? app.borderWidth + 1 : app.borderWidth;
    // Two explicit accessibility nodes per tile: the tile itself
    // ("<native>, <english>", button, selected) and the speaker button
    // ("<Listen> <native>", button). Texts and icons are excluded because
    // the labels already carry them.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: selected,
      label: '${option.nativeName}, $englishName',
      onTap: onTap,
      child: Material(
        color: selected ? app.tint(p.primaryContainer) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: BorderSide(color: borderColor, width: width),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ExcludeSemantics(
                  child: Text(
                    option.nativeName,
                    style: app.text.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ExcludeSemantics(
                  child: Text(
                    englishName,
                    style: app.text.caption.copyWith(color: p.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: onPlay == null
                            ? const SizedBox(height: Tokens.sizeTouchTargetMin)
                            : Semantics(
                                container: true,
                                button: true,
                                label: '$listenLabel ${option.nativeName}',
                                excludeSemantics: true,
                                onTap: onPlay,
                                child: TextButton.icon(
                                  onPressed: onPlay,
                                  style: TextButton.styleFrom(
                                    foregroundColor: p.primary,
                                    minimumSize: const Size(
                                      Tokens.sizeTouchTargetMin,
                                      Tokens.sizeTouchTargetMin,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Tokens.space2,
                                    ),
                                    textStyle: app.text.label,
                                  ),
                                  icon: const Icon(Icons.volume_up_outlined),
                                  label: Text(
                                    listenLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: Tokens.space1),
                    ExcludeSemantics(
                      child: selected
                          ? Icon(Icons.check_circle, color: p.primary)
                          : Icon(Icons.translate, color: p.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.option,
    required this.englishName,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final LanguageOption option;
  final String englishName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final fg = selected ? p.primary : p.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.nativeName}, $englishName',
      excludeSemantics: true,
      child: Material(
        color: selected ? app.tint(p.primaryContainer) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusChip),
          side: BorderSide(
            color: selected ? p.primary : p.border,
            width: selected ? app.borderWidth + 1 : app.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Tokens.sizeTouchTargetMin,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.space3,
                vertical: Tokens.space2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (selected) ...<Widget>[
                    Icon(Icons.check, size: Tokens.space4, color: fg),
                    const SizedBox(width: Tokens.space1),
                  ],
                  Text(
                    option.nativeName,
                    style: app.text.label.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
