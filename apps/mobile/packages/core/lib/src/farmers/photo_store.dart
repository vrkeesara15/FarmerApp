import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where processed photos live until their upload completes.
abstract interface class PhotoStore {
  /// Writes [bytes] under [fileName] and returns the absolute path.
  Future<String> save(String fileName, Uint8List bytes);

  /// Reads a saved photo, or `null` when gone.
  Future<Uint8List?> read(String path);
}

/// Keeps photos in memory (tests, previews).
class MemoryPhotoStore implements PhotoStore {
  /// Saved bytes by path.
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<String> save(String fileName, Uint8List bytes) async {
    final path = 'memory://photos/$fileName';
    files[path] = bytes;
    return path;
  }

  @override
  Future<Uint8List?> read(String path) async => files[path];
}

/// Photos under `<app documents>/photos`.
class DocumentsPhotoStore implements PhotoStore {
  /// Creates the store.
  const DocumentsPhotoStore({this.subdirectory = 'photos'});

  /// Folder inside the documents directory.
  final String subdirectory;

  @override
  Future<String> save(String fileName, Uint8List bytes) async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/$subdirectory',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<Uint8List?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }
}
