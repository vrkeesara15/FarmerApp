import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// The live camera behind F21 / A40: a preview the `CameraGuideOverlay`
/// sits on, and a shutter. `image_picker` cannot draw an overlay on the
/// system camera, so the crop doctor uses the `camera` plugin.
abstract interface class GuidedCamera {
  /// Opens the back camera; throws [GuidedCameraException] when it cannot
  /// (permission refused, no camera).
  Future<void> initialize();

  /// The live preview (fills its box).
  Widget buildPreview(BuildContext context);

  /// Takes a picture and returns the encoded bytes.
  Future<Uint8List> takePicture();

  /// Releases the camera.
  Future<void> dispose();
}

/// The camera could not be used.
class GuidedCameraException implements Exception {
  /// Creates the exception.
  const GuidedCameraException(this.code, [this.message = '']);

  /// `permission_denied`, `no_camera` or `camera_error`.
  final String code;

  /// Detail (logged only).
  final String message;

  @override
  String toString() => 'GuidedCameraException($code: $message)';
}

/// Makes a fresh [GuidedCamera] each time a camera screen opens.
typedef GuidedCameraFactory = GuidedCamera Function();

/// [GuidedCamera] over the `camera` plugin (CameraX on Android): back
/// camera, no audio, JPEG, 720p preview (photos are resized to 1280 px by
/// `PhotoProcessor` anyway, NF-004).
class PluginGuidedCamera implements GuidedCamera {
  /// Creates the camera.
  PluginGuidedCamera({this.preset = ResolutionPreset.high});

  /// Capture resolution.
  final ResolutionPreset preset;

  CameraController? _controller;

  @override
  Future<void> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const GuidedCameraException('no_camera');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
    } on CameraException catch (e) {
      throw GuidedCameraException(
        e.code.contains('Access') || e.code.contains('ermission')
            ? 'permission_denied'
            : 'camera_error',
        e.description ?? e.code,
      );
    }
  }

  @override
  Widget buildPreview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 720,
          height: controller.value.previewSize?.width ?? 1280,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Future<Uint8List> takePicture() async {
    final controller = _controller;
    if (controller == null) {
      throw const GuidedCameraException('camera_error', 'not initialised');
    }
    try {
      final file = await controller.takePicture();
      return await file.readAsBytes();
    } on CameraException catch (e) {
      throw GuidedCameraException('camera_error', e.description ?? e.code);
    }
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

/// Scriptable camera (tests, previews): a plain preview and queued shots.
class FakeGuidedCamera implements GuidedCamera {
  /// Creates the camera with the shots it returns in order.
  FakeGuidedCamera([Iterable<Uint8List> shots = const <Uint8List>[]])
    : _shots = Queue<Uint8List>.of(shots);

  final Queue<Uint8List> _shots;

  /// Throws this from [initialize] when set.
  GuidedCameraException? failWith;

  /// Pictures taken.
  int taken = 0;

  /// Open now.
  bool open = false;

  /// Queues another shot.
  void enqueue(Uint8List bytes) => _shots.add(bytes);

  @override
  Future<void> initialize() async {
    final f = failWith;
    if (f != null) throw f;
    open = true;
  }

  @override
  Widget buildPreview(BuildContext context) => const DecoratedBox(
    key: Key('fake-camera-preview'),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF2E5B34), Color(0xFF16311A)],
      ),
    ),
  );

  @override
  Future<Uint8List> takePicture() async {
    taken += 1;
    if (_shots.isEmpty) {
      throw const GuidedCameraException('camera_error', 'no shot queued');
    }
    return _shots.removeFirst();
  }

  @override
  Future<void> dispose() async => open = false;
}
