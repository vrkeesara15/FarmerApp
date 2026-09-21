// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: design/tokens.json. Regenerate with `dart run tool/gen_tokens.dart`.
// ignore_for_file: public_member_api_docs

import 'dart:ui';

/// Semantic colour palette for one theme (see design/tokens.json).
class TokenPalette {
  const TokenPalette({
    required this.primary,
    required this.primaryHover,
    required this.primaryContainer,
    required this.primaryOn,
    required this.secondary,
    required this.secondaryContainer,
    required this.secondaryOn,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderStrong,
    required this.surface,
    required this.background,
    required this.statusSuccess,
    required this.statusSuccessContainer,
    required this.statusWarning,
    required this.statusWarningContainer,
    required this.statusDanger,
    required this.statusDangerContainer,
    required this.statusInfo,
    required this.statusInfoContainer,
    required this.confidenceHigh,
    required this.confidenceMedium,
    required this.confidenceLow,
    required this.visitVerified,
    required this.visitPartial,
    required this.visitUnverified,
  });

  final Color primary;
  final Color primaryHover;
  final Color primaryContainer;
  final Color primaryOn;
  final Color secondary;
  final Color secondaryContainer;

  /// NF-009: sunlight uses white on the dark amber (5.59:1); black was 3.75:1.
  final Color secondaryOn;
  final Color text;
  final Color textSecondary;

  /// NF-009: 4.80:1 on background (was #8A8076 at 3.61:1, below AA for body text).
  final Color textMuted;

  /// Decorative hairline between rows and around cards. WCAG 1.4.11 does not apply: it carries no state.
  final Color border;

  /// NF-009 / WCAG 1.4.11: the boundary of an interactive control (text field, outlined button). 5.51:1 in light, 4.06:1 in dark, black in sunlight.
  final Color borderStrong;
  final Color surface;
  final Color background;

  /// NF-009: 5.30:1 on successContainer (was #2E7D32 at 4.45:1).
  final Color statusSuccess;
  final Color statusSuccessContainer;

  /// NF-009: 5.58:1 on warningContainer (was #B26A00 at 3.70:1).
  final Color statusWarning;
  final Color statusWarningContainer;

  /// NF-009: dark raised to #F4706D, 5.37:1 on dangerContainer (was #EF5350 at 4.38:1).
  final Color statusDanger;
  final Color statusDangerContainer;
  final Color statusInfo;
  final Color statusInfoContainer;
  final Color confidenceHigh;
  final Color confidenceMedium;

  /// Provisional: neutral grey with dashed border
  final Color confidenceLow;
  final Color visitVerified;
  final Color visitPartial;

  /// Outline style
  final Color visitUnverified;
}

/// A text style token from the mobile type scale (sizes in sp).
class TokenTextStyle {
  const TokenTextStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.fontWeight,
  });
  final double fontSize;
  final double lineHeight;

  /// 400 or 600 only.
  final int fontWeight;
}

/// Shadow token (only bottom sheets and FAB use it).
class TokenShadow {
  const TokenShadow({
    required this.offsetX,
    required this.offsetY,
    required this.blur,
    required this.spread,
    required this.color,
  });
  final double offsetX;
  final double offsetY;
  final double blur;
  final double spread;
  final Color color;
}

/// All design tokens. Themes: light (default), sunlight, dark.
abstract final class Tokens {
  static const TokenPalette light = TokenPalette(
    primary: Color(0xFF1F6B3A),
    primaryHover: Color(0xFF185630),
    primaryContainer: Color(0xFFDCEFE2),
    primaryOn: Color(0xFFFFFFFF),
    secondary: Color(0xFFE0A21B),
    secondaryContainer: Color(0xFFFBEFCF),
    secondaryOn: Color(0xFF3A2A00),
    text: Color(0xFF2B2520),
    textSecondary: Color(0xFF5E554C),
    textMuted: Color(0xFF756C64),
    border: Color(0xFFE3DDD3),
    borderStrong: Color(0xFF6B635B),
    surface: Color(0xFFFFFFFF),
    background: Color(0xFFFAF7F0),
    statusSuccess: Color(0xFF26702C),
    statusSuccessContainer: Color(0xFFE3F3E4),
    statusWarning: Color(0xFF8A5200),
    statusWarningContainer: Color(0xFFFBEFCF),
    statusDanger: Color(0xFFC62828),
    statusDangerContainer: Color(0xFFFBE4E4),
    statusInfo: Color(0xFF1565C0),
    statusInfoContainer: Color(0xFFE1ECF9),
    confidenceHigh: Color(0xFF26702C),
    confidenceMedium: Color(0xFF8A5200),
    confidenceLow: Color(0xFF756C64),
    visitVerified: Color(0xFF26702C),
    visitPartial: Color(0xFF8A5200),
    visitUnverified: Color(0xFFC62828),
  );

  static const TokenPalette sunlight = TokenPalette(
    primary: Color(0xFF134A27),
    primaryHover: Color(0xFF0E361C),
    primaryContainer: Color(0xFFFFFFFF),
    primaryOn: Color(0xFFFFFFFF),
    secondary: Color(0xFF8A6000),
    secondaryContainer: Color(0xFFFFFFFF),
    secondaryOn: Color(0xFFFFFFFF),
    text: Color(0xFF000000),
    textSecondary: Color(0xFF000000),
    textMuted: Color(0xFF333333),
    border: Color(0xFF000000),
    borderStrong: Color(0xFF000000),
    surface: Color(0xFFFFFFFF),
    background: Color(0xFFFFFFFF),
    statusSuccess: Color(0xFF1B5E20),
    statusSuccessContainer: Color(0xFFFFFFFF),
    statusWarning: Color(0xFF7A4800),
    statusWarningContainer: Color(0xFFFFFFFF),
    statusDanger: Color(0xFF8E1B1B),
    statusDangerContainer: Color(0xFFFFFFFF),
    statusInfo: Color(0xFF0D47A1),
    statusInfoContainer: Color(0xFFFFFFFF),
    confidenceHigh: Color(0xFF1B5E20),
    confidenceMedium: Color(0xFF7A4800),
    confidenceLow: Color(0xFF333333),
    visitVerified: Color(0xFF1B5E20),
    visitPartial: Color(0xFF7A4800),
    visitUnverified: Color(0xFF8E1B1B),
  );

  static const TokenPalette dark = TokenPalette(
    primary: Color(0xFF5DBB7E),
    primaryHover: Color(0xFF7BCB96),
    primaryContainer: Color(0xFF1E3A2A),
    primaryOn: Color(0xFF0B1A10),
    secondary: Color(0xFFF0BE4E),
    secondaryContainer: Color(0xFF3A2E10),
    secondaryOn: Color(0xFF1A1400),
    text: Color(0xFFF2EEE7),
    textSecondary: Color(0xFFC9C2B8),
    textMuted: Color(0xFF9A9188),
    border: Color(0xFF3A3631),
    borderStrong: Color(0xFF8A8078),
    surface: Color(0xFF1E1C19),
    background: Color(0xFF151412),
    statusSuccess: Color(0xFF66BB6A),
    statusSuccessContainer: Color(0xFF1B3A1E),
    statusWarning: Color(0xFFE0A21B),
    statusWarningContainer: Color(0xFF3A2E10),
    statusDanger: Color(0xFFF4706D),
    statusDangerContainer: Color(0xFF3F1A1A),
    statusInfo: Color(0xFF64B5F6),
    statusInfoContainer: Color(0xFF15294A),
    confidenceHigh: Color(0xFF66BB6A),
    confidenceMedium: Color(0xFFE0A21B),
    confidenceLow: Color(0xFF9A9188),
    visitVerified: Color(0xFF66BB6A),
    visitPartial: Color(0xFFE0A21B),
    visitUnverified: Color(0xFFF4706D),
  );

  static const List<String> fontFamilyLatin = <String>[
    'Noto Sans',
    'system-ui',
    'sans-serif',
  ];
  static const List<String> fontFamilyTelugu = <String>[
    'Noto Sans Telugu',
    'Noto Sans',
    'sans-serif',
  ];
  static const List<String> fontFamilyKannada = <String>[
    'Noto Sans Kannada',
    'Noto Sans',
    'sans-serif',
  ];
  static const List<String> fontFamilyDevanagari = <String>[
    'Noto Sans Devanagari',
    'Noto Sans',
    'sans-serif',
  ];
  static const int fontWeightRegular = 400;
  static const int fontWeightSemibold = 600;
  static const String fontFeatures = 'tnum';

  static const TokenTextStyle textDisplay = TokenTextStyle(
    fontSize: 28,
    lineHeight: 36,
    fontWeight: 600,
  );
  static const TokenTextStyle textTitle = TokenTextStyle(
    fontSize: 22,
    lineHeight: 30,
    fontWeight: 600,
  );
  static const TokenTextStyle textHeading = TokenTextStyle(
    fontSize: 18,
    lineHeight: 26,
    fontWeight: 600,
  );
  static const TokenTextStyle textBody = TokenTextStyle(
    fontSize: 16,
    lineHeight: 24,
    fontWeight: 400,
  );
  static const TokenTextStyle textLabel = TokenTextStyle(
    fontSize: 14,
    lineHeight: 20,
    fontWeight: 600,
  );
  static const TokenTextStyle textCaption = TokenTextStyle(
    fontSize: 12,
    lineHeight: 16,
    fontWeight: 400,
  );
  static const double indicLineHeightMultiplier = 1.15;

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space12 = 48;
  static const double spaceScreenPadding = 16;

  static const double radiusInput = 8;
  static const double radiusChip = 8;
  static const double radiusCard = 12;
  static const double radiusSheet = 16;
  static const double radiusPill = 9999;

  static const double sizeTouchTargetMin = 48;
  static const double sizePrimaryButtonHeight = 56;
  static const double sizeIcon = 24;

  static const double borderWidthLight = 1;
  static const double borderWidthSunlight = 2;
  static const double borderWidthDark = 1;

  static const TokenShadow? elevationFlat = null;
  static const TokenShadow elevationSheet = TokenShadow(
    offsetX: 0,
    offsetY: 4,
    blur: 16,
    spread: 0,
    color: Color(0x29000000),
  );
}
