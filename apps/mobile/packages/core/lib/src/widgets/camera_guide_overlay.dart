import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Static overlay for the in-app camera: leaf frame plus three tips
/// (SPEC 13.1 `CameraGuideOverlay`). Place it on top of the camera preview.
class CameraGuideOverlay extends StatelessWidget {
  /// Creates the overlay.
  const CameraGuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Tip(
                    icon: Icons.back_hand_outlined,
                    text: l10n.cameraHoldSteady,
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: _Tip(
                    icon: Icons.wb_sunny_outlined,
                    text: l10n.cameraGoodLight,
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: _Tip(
                    icon: Icons.crop_free,
                    text: l10n.cameraFillFrame,
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
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: p.text.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
        border: Border.all(color: p.primaryOn, width: app.borderWidth),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: p.primaryOn),
          const SizedBox(height: Tokens.space1),
          Text(
            text,
            textAlign: TextAlign.center,
            style: app.text.caption.copyWith(color: p.primaryOn),
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
