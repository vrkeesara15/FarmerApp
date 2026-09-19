import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'tflite_quality_model.dart';

/// [QualityInterpreter] over `tflite_flutter` (LiteRT 1.4 C API, XNNPACK
/// on the CPU). The GPU delegate is not packaged (see the apps'
/// `build.gradle.kts`); inference runs on the plugin's background isolate
/// so the UI thread never waits on it.
class TfliteFlutterInterpreter implements QualityInterpreter {
  TfliteFlutterInterpreter._(this._interpreter, this._isolate);

  /// [QualityInterpreterLoader] for [TfliteQualityModel].
  static Future<QualityInterpreter> load(Uint8List modelBytes) async {
    final options = InterpreterOptions()..threads = 2;
    final interpreter = Interpreter.fromBuffer(modelBytes, options: options)
      ..allocateTensors();
    final isolate = await IsolateInterpreter.create(
      address: interpreter.address,
      debugName: 'crop_quality',
    );
    return TfliteFlutterInterpreter._(interpreter, isolate);
  }

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  // `TensorType.uint8.name` is `uint8`, `float32` is `float32`: the
  // metadata's dtype names.
  static String _typeName(TensorType t) => t.name;

  @override
  List<int> get inputShape => _interpreter.getInputTensor(0).shape;

  @override
  String get inputType => _typeName(_interpreter.getInputTensor(0).type);

  @override
  List<int> get outputShape => _interpreter.getOutputTensor(0).shape;

  @override
  String get outputType => _typeName(_interpreter.getOutputTensor(0).type);

  @override
  Future<List<double>> run(Uint8List rgb) async {
    final shape = outputShape;
    final output = List<List<double>>.generate(
      shape.first,
      (_) => List<double>.filled(shape.last, 0),
    );
    await _isolate.run(rgb, output);
    return output.first;
  }

  @override
  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}
