import 'dart:collection';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// In-app camera capture for farm photos (FA-012; FA-015 later).
///
/// There is deliberately no gallery method: the only way to obtain bytes
/// is [capture], which the real implementation binds to the camera.
abstract interface class CameraSource {
  /// Opens the camera; `null` when the officer cancelled.
  Future<Uint8List?> capture();
}

/// Scriptable camera for tests: returns queued images, then `null`.
class FakeCameraSource implements CameraSource {
  /// Creates the fake with the images to return in order.
  FakeCameraSource([Iterable<Uint8List> images = const <Uint8List>[]])
    : _queue = Queue<Uint8List>.of(images);

  final Queue<Uint8List> _queue;

  /// Number of captures so far.
  int captures = 0;

  /// Queues another image.
  void enqueue(Uint8List bytes) => _queue.add(bytes);

  @override
  Future<Uint8List?> capture() async {
    captures += 1;
    return _queue.isEmpty ? null : _queue.removeFirst();
  }
}

/// [CameraSource] over `image_picker`, camera only (gallery disabled).
class ImagePickerCameraSource implements CameraSource {
  /// Creates the source.
  ImagePickerCameraSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> capture() async {
    final file = await _picker.pickImage(source: ImageSource.camera);
    if (file == null) return null;
    return file.readAsBytes();
  }
}
