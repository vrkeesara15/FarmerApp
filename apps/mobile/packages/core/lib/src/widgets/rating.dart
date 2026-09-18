import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Visual style of [Rating].
enum RatingStyle {
  /// Five faces from very sad to very happy (farmer surfaces).
  faces,

  /// Five stars.
  stars,
}

/// 1-5 rating with faces or stars, each paired with a text label
/// (SPEC 13.1 `Rating`, F61).
class Rating extends StatelessWidget {
  /// Creates the rating.
  const Rating({
    required this.value,
    required this.onChanged,
    this.style = RatingStyle.faces,
    this.title,
    super.key,
  });

  /// Selected value 1-5, or `null` when nothing is selected.
  final int? value;

  /// Selection handler; `null` makes the control read-only.
  final ValueChanged<int>? onChanged;

  /// Faces or stars.
  final RatingStyle style;

  /// Optional title above the control.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final labels = <String>[
      l10n.rating1,
      l10n.rating2,
      l10n.rating3,
      l10n.rating4,
      l10n.rating5,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title ?? l10n.ratingTitle, style: app.text.heading),
        const SizedBox(height: Tokens.space3),
        Row(
          children: <Widget>[
            for (var i = 1; i <= 5; i++) ...<Widget>[
              if (i > 1) const SizedBox(width: Tokens.space1),
              Expanded(
                child: _RatingOption(
                  index: i,
                  label: labels[i - 1],
                  icon: _iconFor(i),
                  selected: value == i,
                  highlighted:
                      style == RatingStyle.stars &&
                      value != null &&
                      i <= value!,
                  onTap: onChanged == null ? null : () => onChanged!(i),
                  color: _colorFor(i, p),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  IconData _iconFor(int i) {
    if (style == RatingStyle.stars) return Icons.star_outline;
    return switch (i) {
      1 => Icons.sentiment_very_dissatisfied_outlined,
      2 => Icons.sentiment_dissatisfied_outlined,
      3 => Icons.sentiment_neutral_outlined,
      4 => Icons.sentiment_satisfied_outlined,
      _ => Icons.sentiment_very_satisfied_outlined,
    };
  }

  Color _colorFor(int i, TokenPalette p) {
    if (style == RatingStyle.stars) return p.secondary;
    return switch (i) {
      1 || 2 => p.statusDanger,
      3 => p.statusWarning,
      _ => p.statusSuccess,
    };
  }
}

class _RatingOption extends StatelessWidget {
  const _RatingOption({
    required this.index,
    required this.label,
    required this.icon,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    required this.color,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final active = selected || highlighted;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$index, $label',
      child: Material(
        color: selected ? app.tint(p.primaryContainer) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusChip),
          side: BorderSide(
            color: selected ? color : p.border,
            width: selected ? app.borderWidth + 1 : app.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Tokens.sizePrimaryButtonHeight + Tokens.space4,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.space1,
                vertical: Tokens.space2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    icon,
                    size: Tokens.space8,
                    color: active ? color : p.textMuted,
                  ),
                  const SizedBox(height: Tokens.space1),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: app.text.caption.copyWith(
                      color: active ? p.text : p.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
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
