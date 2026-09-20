import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show immutable;

/// One result from the device's speech recogniser.
@immutable
class SpeechResult {
  /// Creates the result.
  const SpeechResult(this.text, {this.isFinal = false});

  /// What was heard so far.
  final String text;

  /// The recogniser considers this the final transcription.
  final bool isFinal;

  @override
  bool operator ==(Object other) =>
      other is SpeechResult && other.text == text && other.isFinal == isFinal;

  @override
  int get hashCode => Object.hash(text, isFinal);
}

/// Why dictation could not start.
enum SpeechFailure {
  /// The device has no speech recognition service (common on cheap
  /// Android phones without Google app). Typing always works.
  unavailable,

  /// The microphone permission was refused.
  permissionDenied,

  /// The service has no model for the app's language.
  localeUnsupported,

  /// The service failed mid-way.
  error,
}

/// Dictation could not start or stopped early.
class SpeechUnavailable implements Exception {
  /// Creates the exception.
  const SpeechUnavailable(this.reason);

  /// What went wrong.
  final SpeechFailure reason;

  @override
  String toString() => 'SpeechUnavailable(${reason.name})';
}

/// Android speech-to-text as FA-005 uses it: a microphone on every
/// free-text field, in the app's current language.
///
/// Voice is never required — [VoiceTextField] keeps the keyboard and shows
/// a one-line explanation when the device has no speech service.
abstract interface class SpeechService {
  /// Whether the device can transcribe [locale].
  Future<bool> isAvailable(Locale locale);

  /// Listens until [stop] is called or the recogniser decides it is done.
  /// Emits partial results as they arrive, then one final result.
  Stream<SpeechResult> listen(Locale locale);

  /// Stops listening (keeps whatever was heard).
  Future<void> stop();

  /// Stops and throws the partial result away.
  Future<void> cancel();
}

/// The device has no speech service: dictation is offered as unavailable.
class NoSpeechService implements SpeechService {
  /// Creates the service.
  const NoSpeechService();

  @override
  Future<bool> isAvailable(Locale locale) async => false;

  @override
  Stream<SpeechResult> listen(Locale locale) => Stream<SpeechResult>.error(
    const SpeechUnavailable(SpeechFailure.unavailable),
  );

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

/// Scriptable [SpeechService] for tests, goldens and previews.
class FakeSpeechService implements SpeechService {
  /// Creates the fake.
  FakeSpeechService({
    this.available = true,
    this.script = const <SpeechResult>[],
  });

  /// What [isAvailable] answers.
  bool available;

  /// Results handed out on the next [listen], in order.
  List<SpeechResult> script;

  /// Locales [listen] was called with.
  final List<Locale> listened = <Locale>[];

  /// [stop] calls.
  int stops = 0;

  /// [cancel] calls.
  int cancels = 0;

  StreamController<SpeechResult>? _controller;

  /// Pushes one more result into a live session (tests drive the UI with
  /// this when they need to interleave pumps).
  void emit(SpeechResult result) => _controller?.add(result);

  @override
  Future<bool> isAvailable(Locale locale) async => available;

  @override
  Stream<SpeechResult> listen(Locale locale) {
    listened.add(locale);
    if (!available) {
      return Stream<SpeechResult>.error(
        const SpeechUnavailable(SpeechFailure.unavailable),
      );
    }
    final controller = StreamController<SpeechResult>();
    _controller = controller;
    for (final r in script) {
      controller.add(r);
    }
    if (script.any((r) => r.isFinal)) unawaited(controller.close());
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stops += 1;
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> cancel() async {
    cancels += 1;
    await _controller?.close();
    _controller = null;
  }
}
