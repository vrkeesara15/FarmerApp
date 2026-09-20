import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';

/// Rounded surface card used by the M7 officer screens.
class FieldCard extends StatelessWidget {
  /// Creates the card.
  const FieldCard({
    required this.child,
    this.color,
    this.borderColor,
    this.onTap,
    super.key,
  });

  /// Card body.
  final Widget child;

  /// Background; defaults to the surface colour.
  final Color? color;

  /// Border; defaults to the theme border.
  final Color? borderColor;

  /// Tap handler.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space3),
      child: Material(
        color: color ?? app.palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: borderColor == null
              ? app.borderSide
              : BorderSide(color: borderColor!, width: app.borderWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? child : InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

/// A small caption line, e.g. "As of 09:14" or "Will sync".
class FieldCaption extends StatelessWidget {
  /// Creates the caption.
  const FieldCaption(this.text, {this.icon, this.color, super.key});

  /// What it says.
  final String text;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional colour override.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = color ?? app.palette.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: c),
          const SizedBox(width: Tokens.space1),
        ],
        Flexible(
          child: Text(text, style: app.text.caption.copyWith(color: c)),
        ),
      ],
    );
  }
}

/// Bar sparkline for the A60 verified-visit trend. Values are small
/// counts, so bars read better than a line on a 360 dp screen.
class Sparkline extends StatelessWidget {
  /// Creates the sparkline.
  const Sparkline({required this.values, this.height = 48, super.key});

  /// One value per day, oldest first.
  final List<int> values;

  /// Drawing height.
  final double height;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final max = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final (i, v) in values.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  key: Key('sparkline-bar-$i'),
                  height: max == 0 ? 2 : (2 + (height - 2) * v / max),
                  decoration: BoxDecoration(
                    color: v == 0 ? p.border : p.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A "targets vs actual" row: label, `actual of target`, progress bar.
class TargetRow extends StatelessWidget {
  /// Creates the row.
  const TargetRow({
    required this.label,
    required this.actualText,
    required this.actual,
    this.target,
    this.targetText,
    super.key,
  });

  /// What is being measured.
  final String label;

  /// Pre-formatted actual (paise become rupees before they get here).
  final String actualText;

  /// Actual as a number, for the bar.
  final num actual;

  /// Target as a number; null means the tenant set none.
  final num? target;

  /// Pre-formatted target.
  final String? targetText;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final t = target;
    final fraction = t == null || t <= 0
        ? null
        : (actual / t).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: app.text.label.copyWith(color: p.textSecondary)),
          Text(
            t == null
                ? actualText
                : l10n.perfOfTarget(actualText, targetText ?? '$t'),
            style: app.text.label,
          ),
          const SizedBox(height: Tokens.space1),
          if (fraction == null)
            FieldCaption(l10n.perfNoTarget)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: p.border,
                color: fraction >= 1 ? p.statusSuccess : p.primary,
              ),
            ),
        ],
      ),
    );
  }
}
