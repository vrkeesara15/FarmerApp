import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../photo/photo_quality.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'app_button.dart';
import 'photo_tip_text.dart';

/// Photo review card for A41 / F22: thumbnail, size, quality badge with the
/// retake tip, and Retake / Use buttons (FM-004, NF-004).
///
/// Pass `quality: null` while the on-device gate is still running; "Use
/// photo" is enabled only for an acceptable result.
class PhotoReviewCard extends StatelessWidget {
  /// Creates the card.
  const PhotoReviewCard({
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.onRetake,
    required this.onUse,
    this.quality,
    this.thumbnail,
    this.index,
    this.total,
    super.key,
  });

  /// Encoded size of the processed photo.
  final int sizeBytes;

  /// Pixel width of the processed photo.
  final int width;

  /// Pixel height of the processed photo.
  final int height;

  /// Quality gate result; null while checking.
  final PhotoQualityResult? quality;

  /// Thumbnail (usually a `MemoryImage` of the processed bytes).
  final ImageProvider<Object>? thumbnail;

  /// 1-based position when reviewing several photos (up to 3).
  final int? index;

  /// Number of photos when reviewing several.
  final int? total;

  /// Opens the camera again.
  final VoidCallback onRetake;

  /// Accepts the photo.
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final q = quality;

    final title = index != null && total != null
        ? l10n.photoReviewTitle(index!, total!)
        : l10n.photoReviewHeading;
    final sizeText = l10n.photoSizeKb(sizeBytes ~/ 1024);
    final dimensions = l10n.photoDimensions(width, height);

    final (
      Color color,
      Color container,
      IconData icon,
      String badge,
    ) = q == null
        ? (
            p.statusInfo,
            app.tint(p.statusInfoContainer),
            Icons.hourglass_top_outlined,
            l10n.photoQualityChecking,
          )
        : q.isTooDark
        ? (
            p.statusWarning,
            app.tint(p.statusWarningContainer),
            Icons.brightness_low_outlined,
            l10n.photoQualityDark,
          )
        : q.isBlurry
        ? (
            p.statusDanger,
            app.tint(p.statusDangerContainer),
            Icons.blur_on,
            l10n.photoQualityBlurry,
          )
        : (
            p.statusSuccess,
            app.tint(p.statusSuccessContainer),
            Icons.check_circle_outline,
            l10n.photoQualityOk,
          );
    final tip = q == null ? null : l10n.photoTip(q.tipKey);
    final usable = q?.isAcceptable ?? false;

    return Semantics(
      container: true,
      label: '$title, $badge, $sizeText',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Thumbnail(image: thumbnail),
                  const SizedBox(width: Tokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: app.text.heading),
                        const SizedBox(height: Tokens.space1),
                        Text(
                          dimensions,
                          style: app.text.caption.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        Text(sizeText, style: app.text.body),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space3),
              _QualityBadge(
                color: color,
                container: container,
                icon: icon,
                label: badge,
              ),
              if (tip != null) ...<Widget>[
                const SizedBox(height: Tokens.space2),
                Text(tip, style: app.text.body.copyWith(color: color)),
              ],
              const SizedBox(height: Tokens.space4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppButton(
                      label: l10n.photoRetake,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      icon: Icons.refresh,
                      onPressed: onRetake,
                    ),
                  ),
                  const SizedBox(width: Tokens.space3),
                  Expanded(
                    child: AppButton(
                      label: l10n.photoUse,
                      size: AppButtonSize.medium,
                      icon: Icons.check,
                      onPressed: usable ? onUse : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.image});

  final ImageProvider<Object>? image;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final image = this.image;
    return Container(
      width: Tokens.space12 * 2,
      height: Tokens.space12 * 1.5,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: app.tint(p.primaryContainer),
        borderRadius: BorderRadius.circular(Tokens.radiusInput),
        border: Border.all(color: p.border, width: app.borderWidth),
      ),
      child: image == null
          ? Icon(Icons.photo_outlined, color: p.primary)
          : ExcludeSemantics(
              child: Image(image: image, fit: BoxFit.cover),
            ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({
    required this.color,
    required this.container,
    required this.icon,
    required this.label,
  });

  final Color color;
  final Color container;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Material(
      color: container,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        side: BorderSide(color: color, width: app.borderWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space3,
          vertical: Tokens.space1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: Tokens.space4, color: color),
            const SizedBox(width: Tokens.space1),
            Flexible(
              child: Text(
                label,
                style: app.text.label.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
