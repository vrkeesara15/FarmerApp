import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Loading placeholders (SPEC 13.1 `Skeletons`).
///
/// Static blocks (no shimmer) to stay cheap on low-end devices. Use
/// [Skeletons.line], [Skeletons.card] or [Skeletons.list].
class Skeletons extends StatelessWidget {
  /// A single text-line placeholder.
  const Skeletons.line({
    this.width = double.infinity,
    this.height = Tokens.space4,
    super.key,
  }) : _kind = _Kind.line,
       count = 1;

  /// A card-shaped placeholder with avatar and two lines.
  const Skeletons.card({super.key})
    : _kind = _Kind.card,
      width = double.infinity,
      height = 0,
      count = 1;

  /// [count] stacked card placeholders.
  const Skeletons.list({this.count = 3, super.key})
    : _kind = _Kind.list,
      width = double.infinity,
      height = 0;

  final _Kind _kind;

  /// Width of a [Skeletons.line].
  final double width;

  /// Height of a [Skeletons.line].
  final double height;

  /// Number of cards in a [Skeletons.list].
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final child = switch (_kind) {
      _Kind.line => _Block(width: width, height: height),
      _Kind.card => const _Card(),
      _Kind.list => Column(
        children: <Widget>[
          for (var i = 0; i < count; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: Tokens.space3),
            const _Card(),
          ],
        ],
      ),
    };
    return Semantics(
      label: l10n.skeletonLoading,
      child: ExcludeSemantics(child: child),
    );
  }
}

enum _Kind { line, card, list }

class _Block extends StatelessWidget {
  const _Block({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: app.tint(app.palette.border),
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
        border: app.isSunlight ? Border.fromBorderSide(app.borderSide) : null,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Container(
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: app.palette.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Row(
        children: <Widget>[
          const _Block(width: Tokens.space12, height: Tokens.space12),
          const SizedBox(width: Tokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _Block(width: double.infinity, height: Tokens.space4),
                const SizedBox(height: Tokens.space2),
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: Container(
                    height: Tokens.space3,
                    decoration: BoxDecoration(
                      color: app.tint(app.palette.border),
                      borderRadius: BorderRadius.circular(Tokens.radiusChip),
                      border: app.isSunlight
                          ? Border.fromBorderSide(app.borderSide)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
