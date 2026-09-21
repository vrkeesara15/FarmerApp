import 'package:flutter/material.dart';

import '../tokens/tokens.g.dart';

/// The two mobile themes from SPEC 13.1.
///
/// * [light] is the default warm "village agri shop" look.
/// * [sunlight] is the high-contrast outdoor theme: pure white background,
///   black text, 2 dp borders, darker primary, no tinted containers.
enum AppThemeMode {
  /// Default theme.
  light,

  /// High-contrast theme for bright sunlight.
  sunlight,
}

/// Locales whose scripts need ~15% more line height (SPEC 13.1 typography).
const Set<String> indicLanguageCodes = <String>{'te', 'kn', 'hi', 'mr'};

/// The mobile type scale as ready-to-use [TextStyle]s.
///
/// All styles use tabular figures and weights 400/600 only. Body text is never
/// below 16 sp (NF-009).
@immutable
class AppTextStyles {
  /// Creates the six styles of the scale.
  const AppTextStyles({
    required this.display,
    required this.title,
    required this.heading,
    required this.body,
    required this.label,
    required this.caption,
  });

  /// Builds the scale for [locale], adding Indic line height when needed.
  factory AppTextStyles.forLocale(Locale? locale, {required Color color}) {
    final indic =
        locale != null && indicLanguageCodes.contains(locale.languageCode);
    final multiplier = indic ? Tokens.indicLineHeightMultiplier : 1.0;
    final fallback = _fallbackFor(locale);
    TextStyle build(TokenTextStyle t) {
      return TextStyle(
        fontSize: t.fontSize,
        height: (t.lineHeight * multiplier) / t.fontSize,
        fontWeight: t.fontWeight == Tokens.fontWeightSemibold
            ? FontWeight.w600
            : FontWeight.w400,
        fontFamily: Tokens.fontFamilyLatin.first,
        fontFamilyFallback: fallback,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
      );
    }

    return AppTextStyles(
      display: build(Tokens.textDisplay),
      title: build(Tokens.textTitle),
      heading: build(Tokens.textHeading),
      body: build(Tokens.textBody),
      label: build(Tokens.textLabel),
      caption: build(Tokens.textCaption),
    );
  }

  /// 28/36 semibold.
  final TextStyle display;

  /// 22/30 semibold.
  final TextStyle title;

  /// 18/26 semibold.
  final TextStyle heading;

  /// 16/24 regular. Minimum body size.
  final TextStyle body;

  /// 14/20 semibold. Buttons, chips, field labels.
  final TextStyle label;

  /// 12/16 regular. Never used for essential farmer-facing text.
  final TextStyle caption;

  static List<String> _fallbackFor(Locale? locale) {
    switch (locale?.languageCode) {
      case 'te':
        return Tokens.fontFamilyTelugu;
      case 'kn':
        return Tokens.fontFamilyKannada;
      case 'hi':
      case 'mr':
        return Tokens.fontFamilyDevanagari;
      default:
        return <String>[
          ...Tokens.fontFamilyLatin.skip(1),
          ...Tokens.fontFamilyTelugu.take(1),
          ...Tokens.fontFamilyKannada.take(1),
          ...Tokens.fontFamilyDevanagari.take(1),
        ];
    }
  }
}

/// Theme extension carrying the semantic tokens widgets read from.
///
/// Widgets must never use raw colours or sizes; they read `context.app`.
@immutable
class AppThemeData extends ThemeExtension<AppThemeData> {
  /// Creates the extension.
  const AppThemeData({
    required this.mode,
    required this.palette,
    required this.borderWidth,
    required this.text,
  });

  /// Which theme this is.
  final AppThemeMode mode;

  /// Semantic colours for this theme.
  final TokenPalette palette;

  /// 1 dp in Light, 2 dp in Sunlight.
  final double borderWidth;

  /// Locale-aware type scale.
  final AppTextStyles text;

  /// True for the high-contrast theme.
  bool get isSunlight => mode == AppThemeMode.sunlight;

  /// Standard 1-px (or 2-px in Sunlight) border side: the decorative hairline
  /// between rows and around cards.
  BorderSide get borderSide =>
      BorderSide(color: palette.border, width: borderWidth);

  /// The boundary of an interactive control (text field, outlined button).
  ///
  /// NF-009 / WCAG 1.4.11 asks for 3:1 against the background for anything
  /// that identifies a control. The decorative [borderSide] is 1.35:1 in the
  /// Light theme by design -- a hairline that reads as a divider, not as an
  /// edge -- so a field that used it was invisible to a farmer in sunlight or
  /// with low vision. `borderStrong` is the same shape at 5.5:1.
  BorderSide get controlBorderSide =>
      BorderSide(color: palette.borderStrong, width: borderWidth);

  /// Tinted container colour, or plain surface in Sunlight (no tints there).
  Color tint(Color container) => isSunlight ? palette.surface : container;

  @override
  AppThemeData copyWith({
    AppThemeMode? mode,
    TokenPalette? palette,
    double? borderWidth,
    AppTextStyles? text,
  }) {
    return AppThemeData(
      mode: mode ?? this.mode,
      palette: palette ?? this.palette,
      borderWidth: borderWidth ?? this.borderWidth,
      text: text ?? this.text,
    );
  }

  @override
  AppThemeData lerp(ThemeExtension<AppThemeData>? other, double t) {
    // Themes are discrete; snap at the midpoint.
    if (other is! AppThemeData) return this;
    return t < 0.5 ? this : other;
  }
}

/// Builds Material [ThemeData] for the FarmerApp mobile themes.
abstract final class AppTheme {
  /// Builds the theme for [mode] and [locale].
  static ThemeData build(AppThemeMode mode, {Locale? locale}) {
    final palette = switch (mode) {
      AppThemeMode.light => Tokens.light,
      AppThemeMode.sunlight => Tokens.sunlight,
    };
    final borderWidth = switch (mode) {
      AppThemeMode.light => Tokens.borderWidthLight,
      AppThemeMode.sunlight => Tokens.borderWidthSunlight,
    };
    final text = AppTextStyles.forLocale(locale, color: palette.text);
    final ext = AppThemeData(
      mode: mode,
      palette: palette,
      borderWidth: borderWidth,
      text: text,
    );
    final sunlight = mode == AppThemeMode.sunlight;

    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: palette.primary,
      onPrimary: palette.primaryOn,
      primaryContainer: palette.primaryContainer,
      onPrimaryContainer: palette.text,
      secondary: palette.secondary,
      onSecondary: palette.secondaryOn,
      secondaryContainer: palette.secondaryContainer,
      onSecondaryContainer: palette.secondaryOn,
      error: palette.statusDanger,
      onError: palette.primaryOn,
      errorContainer: palette.statusDangerContainer,
      onErrorContainer: palette.statusDanger,
      surface: palette.surface,
      onSurface: palette.text,
      onSurfaceVariant: palette.textSecondary,
      // Material paints control outlines from `outline` and dividers from
      // `outlineVariant` (NF-009: 3:1 for the first, decorative for the second).
      outline: palette.borderStrong,
      outlineVariant: palette.border,
      surfaceContainerHighest: palette.background,
    );

    // NF-009 / WCAG 1.4.11: a text field's outline identifies a control, so it
    // needs 3:1 -- unlike the dividers and card edges, which keep `border`.
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Tokens.radiusInput),
      borderSide: BorderSide(color: palette.borderStrong, width: borderWidth),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.surface,
      dividerColor: palette.border,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: Tokens.fontFamilyLatin.first,
      fontFamilyFallback: text.body.fontFamilyFallback,
      textTheme: TextTheme(
        displaySmall: text.display,
        headlineSmall: text.title,
        titleLarge: text.title,
        titleMedium: text.heading,
        titleSmall: text.label,
        bodyLarge: text.body,
        bodyMedium: text.body,
        bodySmall: text.caption,
        labelLarge: text.label,
        labelMedium: text.label,
        labelSmall: text.caption,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.title,
        shape: Border(
          bottom: BorderSide(color: palette.border, width: borderWidth),
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: BorderSide(color: palette.border, width: borderWidth),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: palette.primary,
            width: borderWidth + Tokens.borderWidthLight,
          ),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: palette.statusDanger,
            width: borderWidth,
          ),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: palette.statusDanger,
            width: borderWidth + Tokens.borderWidthLight,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.space4,
          vertical: Tokens.space3,
        ),
        labelStyle: text.label.copyWith(color: palette.textSecondary),
        helperStyle: text.caption.copyWith(color: palette.textSecondary),
        errorStyle: text.caption.copyWith(color: palette.statusDanger),
        hintStyle: text.body.copyWith(color: palette.textMuted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Tokens.radiusSheet),
          ),
        ),
        elevation: sunlight ? 0 : Tokens.elevationSheet.blur / 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusSheet),
          side: BorderSide(color: palette.border, width: borderWidth),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.text,
        contentTextStyle: text.body.copyWith(color: palette.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusInput),
        ),
      ),
      iconTheme: IconThemeData(size: Tokens.sizeIcon, color: palette.text),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[ext],
    );
  }
}

/// Convenience access to [AppThemeData] from a [BuildContext].
extension AppThemeContext on BuildContext {
  /// The current FarmerApp theme tokens.
  ///
  /// Falls back to the Light theme when the extension is missing so widgets
  /// still render inside plain Material test harnesses.
  AppThemeData get app {
    return Theme.of(this).extension<AppThemeData>() ??
        AppThemeData(
          mode: AppThemeMode.light,
          palette: Tokens.light,
          borderWidth: Tokens.borderWidthLight,
          text: AppTextStyles.forLocale(
            Localizations.maybeLocaleOf(this),
            color: Tokens.light.text,
          ),
        );
  }
}
