import 'dart:math' as math;

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// NF-009: "WCAG AA contrast", checked over the design tokens themselves
/// rather than over screenshots, so a token changed in `design/tokens.json`
/// fails here before it reaches a farmer standing in a field at noon.
///
/// WCAG 2.2 thresholds used:
/// * **4.5:1** for normal body text (1.4.3). Everything the farmer reads is
///   body size or smaller (16 sp, 14 sp labels, 12 sp captions), so the large
///   text exemption (3:1 at 18 pt / 24 px) never applies to us and is not
///   used here -- 28 sp display text is the one exception and it always sits
///   on `text` over `background`, which passes 4.5 anyway.
/// * **3:1** for the boundary of a control and for a graphical object that
///   carries meaning (1.4.11): the confidence ramp, the visit badges, and the
///   outline of a text field.
///
/// `contrastRatio` itself lives in `lib/src/theme/contrast.dart`: FA-008
/// derives a tenant's primary colour with it at run time, so the check and
/// the derivation must use one implementation, not two.
///
/// The `border` token is deliberately *not* held to 3:1. It is the hairline
/// between rows and around cards; it carries no state and identifies no
/// control, which is exactly the case 1.4.11 excludes. The token a control's
/// outline uses is `borderStrong`, and that one is checked.
void main() {
  const themes = <String, TokenPalette>{
    'light': Tokens.light,
    'sunlight': Tokens.sunlight,
    'dark': Tokens.dark,
  };

  /// Every pair a farmer reads text in.
  List<_Pair> textPairs(TokenPalette p) => <_Pair>[
    _Pair('text on background', p.text, p.background),
    _Pair('text on surface', p.text, p.surface),
    _Pair('textSecondary on background', p.textSecondary, p.background),
    _Pair('textSecondary on surface', p.textSecondary, p.surface),
    // Captions and helper text use textMuted. It is the token most often got
    // wrong, because "muted" reads as "allowed to be faint".
    _Pair('textMuted on background', p.textMuted, p.background),
    _Pair('textMuted on surface', p.textMuted, p.surface),
    _Pair('primaryOn on primary', p.primaryOn, p.primary),
    _Pair('primaryOn on primaryHover', p.primaryOn, p.primaryHover),
    _Pair('secondaryOn on secondary', p.secondaryOn, p.secondary),
    _Pair('primary on surface', p.primary, p.surface),
    _Pair('primary on background', p.primary, p.background),
    _Pair('primary on primaryContainer', p.primary, p.primaryContainer),
    // Status text sits both on its own tinted container and, in Sunlight
    // (where containers collapse to white), on the plain surface.
    _Pair(
      'statusSuccess on container',
      p.statusSuccess,
      p.statusSuccessContainer,
    ),
    _Pair(
      'statusWarning on container',
      p.statusWarning,
      p.statusWarningContainer,
    ),
    _Pair('statusDanger on container', p.statusDanger, p.statusDangerContainer),
    _Pair('statusInfo on container', p.statusInfo, p.statusInfoContainer),
    _Pair('statusSuccess on surface', p.statusSuccess, p.surface),
    _Pair('statusWarning on surface', p.statusWarning, p.surface),
    _Pair('statusDanger on surface', p.statusDanger, p.surface),
    _Pair('statusInfo on surface', p.statusInfo, p.surface),
  ];

  /// Controls and meaningful graphics (WCAG 1.4.11).
  List<_Pair> uiPairs(TokenPalette p) => <_Pair>[
    _Pair('borderStrong on surface', p.borderStrong, p.surface),
    _Pair('borderStrong on background', p.borderStrong, p.background),
    _Pair('confidenceHigh on surface', p.confidenceHigh, p.surface),
    _Pair('confidenceMedium on surface', p.confidenceMedium, p.surface),
    _Pair('confidenceLow on surface', p.confidenceLow, p.surface),
    _Pair('visitVerified on surface', p.visitVerified, p.surface),
    _Pair('visitPartial on surface', p.visitPartial, p.surface),
    _Pair('visitUnverified on surface', p.visitUnverified, p.surface),
    _Pair('primary on surface (FAB, icons)', p.primary, p.surface),
  ];

  for (final entry in themes.entries) {
    group('${entry.key} theme', () {
      final palette = entry.value;

      test('every text pair meets WCAG AA 4.5:1', () {
        final failures = <String>[
          for (final pair in textPairs(palette))
            if (contrastRatio(pair.fg, pair.bg) < 4.5)
              '${pair.name}: ${contrastRatio(pair.fg, pair.bg).toStringAsFixed(2)}:1',
        ];
        expect(
          failures,
          isEmpty,
          reason:
              'NF-009 wants AA on farmer-facing text. Fix design/tokens.json '
              'and re-run `dart run tool/gen_tokens.dart`, not this test.',
        );
      });

      test('controls and meaningful graphics meet WCAG 1.4.11 3:1', () {
        final failures = <String>[
          for (final pair in uiPairs(palette))
            if (contrastRatio(pair.fg, pair.bg) < 3)
              '${pair.name}: ${contrastRatio(pair.fg, pair.bg).toStringAsFixed(2)}:1',
        ];
        expect(failures, isEmpty, reason: 'NF-009 / WCAG 1.4.11');
      });
    });
  }

  test('the Sunlight theme is the strongest of the three', () {
    // It exists for a farmer holding a cheap phone in direct sun; if a change
    // ever made it weaker than Light, the theme has lost its only purpose.
    double worst(TokenPalette p) =>
        textPairs(p)
            .map((pair) => contrastRatio(pair.fg, pair.bg))
            .reduce(math.min);

    expect(worst(Tokens.sunlight), greaterThan(worst(Tokens.light)));
    expect(worst(Tokens.sunlight), greaterThanOrEqualTo(4.5));
  });

  test('the ratio function agrees with the WCAG worked examples', () {
    // Black on white is the definition of 21:1; a colour on itself is 1:1.
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    expect(
      contrastRatio(const Color(0xFF1F6B3A), const Color(0xFF1F6B3A)),
      closeTo(1, 0.001),
    );
    // Symmetric: contrast has no direction.
    expect(
      contrastRatio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
      closeTo(
        contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF767676)),
        0.001,
      ),
    );
    // #767676 on white is the canonical "just passes AA" grey (4.54:1).
    expect(
      contrastRatio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
      closeTo(4.54, 0.02),
    );
  });
}

class _Pair {
  const _Pair(this.name, this.fg, this.bg);

  final String name;
  final Color fg;
  final Color bg;
}
