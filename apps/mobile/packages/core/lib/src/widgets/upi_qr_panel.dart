import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../utils/format.dart';
import 'app_button.dart';

/// State of a UPI collect request.
enum UpiPaymentState {
  /// QR shown, waiting for the farmer to pay.
  waiting,

  /// Payment confirmed.
  paid,

  /// Payment failed or expired.
  failed,
}

/// UPI QR with amount, countdown and waiting/paid/failed states
/// (SPEC 13.1 `UpiQrPanel`).
///
/// The QR is rendered from [qrPayload] (the provider's UPI intent) with
/// `qr_flutter`; an empty payload falls back to [UpiQrPlaceholderPainter]
/// (previews only).
class UpiQrPanel extends StatelessWidget {
  /// Creates the panel.
  const UpiQrPanel({
    required this.state,
    required this.amountPaise,
    this.qrPayload = '',
    this.remaining,
    this.onRetry,
    this.statusText,
    super.key,
  });

  /// Current state.
  final UpiPaymentState state;

  /// Amount in paise.
  final int amountPaise;

  /// UPI intent string encoded in the QR.
  final String qrPayload;

  /// Time left before the QR expires (waiting state).
  final Duration? remaining;

  /// Handler for "Show a new QR" (failed state).
  final VoidCallback? onRetry;

  /// Overrides the state heading (e.g. "QR expired").
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);

    final (Color color, IconData icon, String label) = switch (state) {
      UpiPaymentState.waiting => (
        p.statusInfo,
        Icons.hourglass_top,
        l10n.upiWaiting,
      ),
      UpiPaymentState.paid => (
        p.statusSuccess,
        Icons.check_circle_outline,
        l10n.upiPaid,
      ),
      UpiPaymentState.failed => (
        p.statusDanger,
        Icons.error_outline,
        l10n.upiFailed,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Column(
        children: <Widget>[
          Text(
            l10n.upiAmount,
            style: app.text.label.copyWith(color: p.textSecondary),
          ),
          Text(formatInr(amountPaise), style: app.text.display),
          const SizedBox(height: Tokens.space4),
          Semantics(
            label: l10n.paymentUpiQr,
            image: true,
            child: Container(
              width: 200,
              height: 200,
              padding: const EdgeInsets.all(Tokens.space2),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(Tokens.radiusInput),
                border: Border.fromBorderSide(app.borderSide),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (qrPayload.isEmpty)
                    CustomPaint(
                      painter: UpiQrPlaceholderPainter(
                        payload: qrPayload,
                        color: p.text,
                      ),
                    )
                  else
                    QrImageView(
                      data: qrPayload,
                      padding: EdgeInsets.zero,
                      // Black on white in every theme: scanners need it.
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(
                        color: Colors.black,
                      ),
                    ),
                  if (state != UpiPaymentState.waiting)
                    ColoredBox(
                      color: p.surface.withValues(alpha: 0.85),
                      child: Icon(
                        icon,
                        size: Tokens.space12 + Tokens.space4,
                        color: color,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Tokens.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color),
              const SizedBox(width: Tokens.space2),
              Flexible(
                child: Text(
                  statusText ?? label,
                  textAlign: TextAlign.center,
                  style: app.text.heading.copyWith(color: color),
                ),
              ),
            ],
          ),
          if (state == UpiPaymentState.waiting) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            Text(
              l10n.upiScanHint,
              textAlign: TextAlign.center,
              style: app.text.body.copyWith(color: p.textSecondary),
            ),
            if (remaining != null) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.timer_outlined,
                    size: Tokens.space4,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: Tokens.space1),
                  Text(
                    l10n.upiExpiresIn(formatCountdown(remaining!)),
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ],
          ],
          if (state == UpiPaymentState.failed && onRetry != null) ...<Widget>[
            const SizedBox(height: Tokens.space4),
            AppButton(
              label: l10n.upiRetry,
              icon: Icons.refresh,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Deterministic pseudo-QR pattern derived from [payload].
///
/// Not scannable; it stands in until a QR encoder is wired up.
class UpiQrPlaceholderPainter extends CustomPainter {
  /// Creates the painter.
  const UpiQrPlaceholderPainter({required this.payload, required this.color});

  /// Seed for the pattern.
  final String payload;

  /// Module colour.
  final Color color;

  static const int _modules = 21;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cell = size.shortestSide / _modules;
    var seed = payload.hashCode ^ 0x5F3759DF;
    int next() {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return seed;
    }

    for (var y = 0; y < _modules; y++) {
      for (var x = 0; x < _modules; x++) {
        final finder = _inFinder(x, y);
        final on = finder ?? (next() % 3 == 0);
        if (on) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }
  }

  /// Returns the finder-pattern value for the three corners, else `null`.
  bool? _inFinder(int x, int y) {
    bool? check(int ox, int oy) {
      final dx = x - ox;
      final dy = y - oy;
      if (dx < 0 || dy < 0 || dx > 6 || dy > 6) return null;
      final ring = dx == 0 || dy == 0 || dx == 6 || dy == 6;
      final core = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4;
      return ring || core;
    }

    return check(0, 0) ?? check(_modules - 7, 0) ?? check(0, _modules - 7);
  }

  @override
  bool shouldRepaint(UpiQrPlaceholderPainter oldDelegate) =>
      payload != oldDelegate.payload || color != oldDelegate.color;
}
