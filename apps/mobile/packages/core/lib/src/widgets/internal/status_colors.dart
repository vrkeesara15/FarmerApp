import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Semantic status used by badges, pills and banners.
enum StatusTone {
  /// Success green.
  success,

  /// Warning amber.
  warning,

  /// Danger red.
  danger,

  /// Info blue.
  info,

  /// Neutral grey.
  neutral,
}

/// Resolves a [StatusTone] to foreground and container colours.
extension StatusToneColors on StatusTone {
  /// Foreground (text, icon, border) colour.
  Color foreground(AppThemeData app) {
    final p = app.palette;
    return switch (this) {
      StatusTone.success => p.statusSuccess,
      StatusTone.warning => p.statusWarning,
      StatusTone.danger => p.statusDanger,
      StatusTone.info => p.statusInfo,
      StatusTone.neutral => p.textMuted,
    };
  }

  /// Tinted container colour (plain surface in Sunlight).
  Color container(AppThemeData app) {
    final p = app.palette;
    return app.tint(switch (this) {
      StatusTone.success => p.statusSuccessContainer,
      StatusTone.warning => p.statusWarningContainer,
      StatusTone.danger => p.statusDangerContainer,
      StatusTone.info => p.statusInfoContainer,
      StatusTone.neutral => p.background,
    });
  }
}
