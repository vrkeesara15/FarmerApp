import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Visual variants of [AppButton].
enum AppButtonVariant {
  /// Filled primary action. One per screen.
  primary,

  /// Outlined secondary action.
  secondary,

  /// Text-only tertiary action.
  tertiary,

  /// Filled danger action.
  destructive,
}

/// Sizes of [AppButton].
enum AppButtonSize {
  /// 56 dp, full width by default. Bottom primary actions.
  large,

  /// 48 dp. Inline actions and cards.
  medium,
}

/// The FarmerApp button (SPEC 13.1 `AppButton`).
///
/// Disabled when [onPressed] is `null` or [loading] is `true`. Icons are always
/// paired with the text [label].
class AppButton extends StatelessWidget {
  /// Creates a button.
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.large,
    this.icon,
    this.loading = false,
    this.expand = true,
    super.key,
  });

  /// Visible text. Required: never an icon-only button.
  final String label;

  /// Tap handler; `null` disables the button.
  final VoidCallback? onPressed;

  /// Visual variant.
  final AppButtonVariant variant;

  /// Height class.
  final AppButtonSize size;

  /// Optional leading icon.
  final IconData? icon;

  /// Shows a spinner and disables taps.
  final bool loading;

  /// Whether to stretch to the parent width.
  final bool expand;

  double get _height => switch (size) {
    AppButtonSize.large => Tokens.sizePrimaryButtonHeight,
    AppButtonSize.medium => Tokens.sizeTouchTargetMin,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final enabled = onPressed != null && !loading;
    final l10n = CoreLocalizations.of(context);

    final Color fg;
    final Color bg;
    final BorderSide side;
    switch (variant) {
      case AppButtonVariant.primary:
        fg = p.primaryOn;
        bg = p.primary;
        side = BorderSide(color: p.primary, width: app.borderWidth);
      case AppButtonVariant.secondary:
        fg = p.primary;
        bg = p.surface;
        side = BorderSide(color: p.primary, width: app.borderWidth);
      case AppButtonVariant.tertiary:
        fg = p.primary;
        bg = Colors.transparent;
        side = BorderSide.none;
      case AppButtonVariant.destructive:
        fg = p.primaryOn;
        bg = p.statusDanger;
        side = BorderSide(color: p.statusDanger, width: app.borderWidth);
    }

    final disabledFg = app.isSunlight ? p.textMuted : p.textMuted;
    final disabledBg = variant == AppButtonVariant.tertiary
        ? Colors.transparent
        : app.tint(p.border);

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(
        Size(expand ? double.infinity : 0, _height),
      ),
      fixedSize: WidgetStatePropertyAll<Size>(Size.fromHeight(_height)),
      padding: const WidgetStatePropertyAll<EdgeInsets>(
        EdgeInsets.symmetric(horizontal: Tokens.space4),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
      ),
      side: WidgetStateProperty.resolveWith<BorderSide>((states) {
        if (states.contains(WidgetState.disabled)) {
          return side == BorderSide.none
              ? side
              : side.copyWith(color: disabledFg);
        }
        return side;
      }),
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) return disabledBg;
        if (states.contains(WidgetState.pressed)) {
          return switch (variant) {
            AppButtonVariant.primary => p.primaryHover,
            AppButtonVariant.secondary => app.tint(p.primaryContainer),
            AppButtonVariant.tertiary => app.tint(p.primaryContainer),
            AppButtonVariant.destructive => p.statusDanger,
          };
        }
        return bg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) => states.contains(WidgetState.disabled) ? disabledFg : fg,
      ),
      overlayColor: WidgetStatePropertyAll<Color>(fg.withValues(alpha: 0.12)),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        size == AppButtonSize.large
            ? app.text.body.copyWith(fontWeight: FontWeight.w600)
            : app.text.label,
      ),
      elevation: const WidgetStatePropertyAll<double>(0),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    final Widget content;
    if (loading) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(
            dimension: Tokens.space4,
            child: CircularProgressIndicator(
              strokeWidth: Tokens.borderWidthSunlight,
              color: disabledFg,
            ),
          ),
          const SizedBox(width: Tokens.space2),
          Text(l10n.loading),
        ],
      );
    } else if (icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: Tokens.sizeIcon),
          const SizedBox(width: Tokens.space2),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );
    } else {
      content = Text(label, overflow: TextOverflow.ellipsis);
    }

    final button = FilledButton(
      style: style,
      onPressed: enabled ? onPressed : null,
      child: content,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '${l10n.loading}: $label' : label,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
