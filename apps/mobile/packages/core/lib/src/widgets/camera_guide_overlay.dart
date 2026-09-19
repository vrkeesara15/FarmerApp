import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../photo/photo_quality.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'photo_tip_text.dart';

/// Overlay for the in-app camera: leaf frame plus three tips
/// (SPEC 13.1 `CameraGuideOverlay`). Place it on top of the camera preview.
///
/// Give it the [tipKey] of the last quality-gate result (FM-004) to
/// highlight the matching tip and show the retake line: `photo.tip.blurry`
/// lights "hold steady", `photo.tip.dark` lights "good light" and
/// `photo.tip.not_plant` lights "fill the frame".
class CameraGuideOverlay extends StatelessWidget {
  /// Creates the overlay.
  const CameraGuideOverlay({this.tipKey, super.key});

  /// Key of the retake line shown under the frame (see [PhotoTipKeys]).
  static const Key tipMessageKey = Key('cameraGuideOverlay.tipMessage');

  /// One of [PhotoTipKeys], or null for the static overlay.
  final String? tipKey;

  /// Index of the tip chip lit for [tipKey] (0 hold steady, 1 good light,
  /// 2 fill the frame), or null when nothing needs fixing.
  static int? highlightedTip(String? tipKey) => switch (tipKey) {
    PhotoTipKeys.blurry => 0,
    PhotoTipKeys.dark => 1,
    PhotoTipKeys.notPlant => 2,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final lit = highlightedTip(tipKey);
    final tip = tipKey;
    final tipOk = tip == PhotoTipKeys.ok;
    return Semantics(
      label: l10n.cameraLeafFrame,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.space8),
              child: CustomPaint(
                painter: _LeafFramePainter(
                  color: p.primaryOn,
                  width: app.borderWidth + 1,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.space4,
              vertical: Tokens.space3,
            ),
            child: Text(
              l10n.cameraLeafFrame,
              textAlign: TextAlign.center,
              style: app.text.body.copyWith(color: p.primaryOn),
            ),
          ),
          if (tip != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space4,
                0,
                Tokens.space4,
                Tokens.space3,
              ),
              child: Container(
                key: tipMessageKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.space3,
                  vertical: Tokens.space2,
                ),
                decoration: BoxDecoration(
                  color: p.text.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(Tokens.radiusChip),
                  border: Border.all(
                    color: tipOk ? p.statusSuccess : p.statusWarning,
                    width: app.borderWidth + 1,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      tipOk ? Icons.check_circle_outline : Icons.error_outline,
                      color: tipOk ? p.statusSuccess : p.statusWarning,
                    ),
                    const SizedBox(width: Tokens.space2),
                    Expanded(
                      child: Text(
                        l10n.photoTip(tip),
                        style: app.text.body.copyWith(color: p.primaryOn),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Tip(
                    icon: Icons.back_hand_outlined,
                    text: l10n.cameraHoldSteady,
                    highlighted: lit == 0,
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: _Tip(
                    icon: Icons.wb_sunny_outlined,
                    text: l10n.cameraGoodLight,
                    highlighted: lit == 1,
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: _Tip(
                    icon: Icons.crop_free,
                    text: l10n.cameraFillFrame,
                    highlighted: lit == 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.space4),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({
    required this.icon,
    required this.text,
    this.highlighted = false,
  });

  final IconData icon;
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final accent = highlighted ? p.statusWarning : p.primaryOn;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: p.text.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
        border: Border.all(
          color: accent,
          width: highlighted ? app.borderWidth + 1 : app.borderWidth,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: accent),
          const SizedBox(height: Tokens.space1),
          Text(
            text,
            textAlign: TextAlign.center,
            style: app.text.caption.copyWith(color: accent),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

/// Draws a rounded frame with corner marks and a simple leaf outline.
class _LeafFramePainter extends CustomPainter {
  const _LeafFramePainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    final corner = size.shortestSide / 6;
    // Corner marks.
    final corners = <(Offset, Offset, Offset)>[
      (rect.topLeft, const Offset(1, 0), const Offset(0, 1)),
      (rect.topRight, const Offset(-1, 0), const Offset(0, 1)),
      (rect.bottomLeft, const Offset(1, 0), const Offset(0, -1)),
      (rect.bottomRight, const Offset(-1, 0), const Offset(0, -1)),
    ];
    for (final (origin, dx, dy) in corners) {
      canvas.drawLine(origin, origin + dx * corner, paint);
      canvas.drawLine(origin, origin + dy * corner, paint);
    }
    // Leaf outline.
    final leaf = Path();
    final c = rect.center;
    final h = size.height * 0.6;
    final w = size.width * 0.45;
    leaf.moveTo(c.dx, c.dy - h / 2);
    leaf.quadraticBezierTo(c.dx + w, c.dy - h / 4, c.dx, c.dy + h / 2);
    leaf.quadraticBezierTo(c.dx - w, c.dy - h / 4, c.dx, c.dy - h / 2);
    leaf.moveTo(c.dx, c.dy - h / 2);
    leaf.lineTo(c.dx, c.dy + h / 2);
    canvas.drawPath(leaf, paint..color = color.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_LeafFramePainter oldDelegate) =>
      color != oldDelegate.color || width != oldDelegate.width;
}
