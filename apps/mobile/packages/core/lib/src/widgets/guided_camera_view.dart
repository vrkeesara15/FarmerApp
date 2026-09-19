import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../diagnosis/guided_camera.dart';
import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'app_button.dart';
import 'camera_guide_overlay.dart';

/// F21 / A40: the live camera preview with the [CameraGuideOverlay] on top
/// (leaf frame, three tips, the last retake tip lit) and a big shutter.
class GuidedCameraView extends StatefulWidget {
  /// Creates the view.
  const GuidedCameraView({
    required this.camera,
    required this.onShot,
    this.tipKey,
    this.counter,
    this.busy = false,
    super.key,
  });

  /// The camera (opened here, closed on dispose).
  final GuidedCamera camera;

  /// Receives the encoded shot.
  final Future<void> Function(Uint8List bytes) onShot;

  /// Tip of the last rejected photo (lights the matching overlay tip).
  final String? tipKey;

  /// "Photo 2 of 3".
  final String? counter;

  /// Checking the last shot: the shutter waits.
  final bool busy;

  /// Key of the shutter button.
  static const Key shutterKey = Key('camera-shutter');

  @override
  State<GuidedCameraView> createState() => _GuidedCameraViewState();
}

class _GuidedCameraViewState extends State<GuidedCameraView> {
  late Future<void> _opening = widget.camera.initialize();
  bool _taking = false;

  @override
  void dispose() {
    widget.camera.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    if (_taking || widget.busy) return;
    setState(() => _taking = true);
    try {
      final bytes = await widget.camera.takePicture();
      await widget.onShot(bytes);
    } on GuidedCameraException {
      // The preview stays; the user can shoot again.
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return FutureBuilder<void>(
      future: _opening,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final error = snap.error;
        if (error != null) {
          final denied =
              error is GuidedCameraException &&
              error.code == 'permission_denied';
          return Center(
            key: const Key('camera-error'),
            child: Padding(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.no_photography_outlined,
                    size: 72,
                    color: p.statusWarning,
                  ),
                  const SizedBox(height: Tokens.space3),
                  Text(
                    denied
                        ? l10n.cropDoctorCameraDenied
                        : l10n.cropDoctorCameraError,
                    textAlign: TextAlign.center,
                    style: app.text.title,
                  ),
                  const SizedBox(height: Tokens.space4),
                  AppButton(
                    label: l10n.cropDoctorTryAgain,
                    icon: Icons.refresh,
                    onPressed: () =>
                        setState(() => _opening = widget.camera.initialize()),
                  ),
                ],
              ),
            ),
          );
        }
        final busy = _taking || widget.busy;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            widget.camera.buildPreview(context),
            Column(
              children: <Widget>[
                if (widget.counter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Tokens.space3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.space3,
                        vertical: Tokens.space1,
                      ),
                      decoration: BoxDecoration(
                        color: p.text.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(Tokens.radiusPill),
                      ),
                      child: Text(
                        widget.counter!,
                        key: const Key('camera-counter'),
                        style: app.text.label.copyWith(color: p.primaryOn),
                      ),
                    ),
                  ),
                Expanded(child: CameraGuideOverlay(tipKey: widget.tipKey)),
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.space4),
                  child: Semantics(
                    button: true,
                    label: l10n.cropDoctorTakePhoto,
                    excludeSemantics: true,
                    child: InkResponse(
                      key: GuidedCameraView.shutterKey,
                      onTap: busy ? null : _shoot,
                      radius: 44,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: busy
                              ? p.textMuted
                              : p.primaryOn.withValues(alpha: 0.9),
                          border: Border.all(color: p.primary, width: 6),
                        ),
                        child: busy
                            ? const Padding(
                                padding: EdgeInsets.all(Tokens.space6),
                                child: CircularProgressIndicator(),
                              )
                            : Icon(
                                Icons.camera_alt,
                                size: 36,
                                color: p.primary,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
