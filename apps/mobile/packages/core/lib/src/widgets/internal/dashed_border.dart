import 'package:flutter/material.dart';

/// Paints a dashed rounded-rectangle border (used for "provisional" states).
class DashedBorderPainter extends CustomPainter {
  /// Creates the painter.
  const DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    this.dash = 6,
    this.gap = 4,
  });

  /// Stroke colour.
  final Color color;

  /// Stroke width in dp.
  final double strokeWidth;

  /// Corner radius in dp.
  final double radius;

  /// Dash length.
  final double dash;

  /// Gap length.
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(strokeWidth / 2),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        radius != oldDelegate.radius;
  }
}

/// Wraps [child] in a dashed border.
class DashedBorder extends StatelessWidget {
  /// Creates the wrapper.
  const DashedBorder({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.child,
    super.key,
  });

  /// Stroke colour.
  final Color color;

  /// Stroke width in dp.
  final double strokeWidth;

  /// Corner radius in dp.
  final double radius;

  /// Content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(
        color: color,
        strokeWidth: strokeWidth,
        radius: radius,
      ),
      child: child,
    );
  }
}
