import 'dart:async';
import 'dart:ui' show Locale;

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Android speech-to-text for FA-005, in the app's current language.
///
/// The plugin is asked for the locale that matches the app language
/// (`te-IN`, `kn-IN`, `hi-IN`, `mr-IN`, `en-IN`). A phone without a speech
/// service — common on the cheap devices in NF-001 — simply answers
/// [isAvailable] false and [VoiceTextField] explains that typing still
/// works.
class PluginSpeechService implements SpeechService {
  /// Creates the service.
  PluginSpeechService({stt.SpeechToText? plugin})
    : _speech = plugin ?? stt.SpeechToText();

  final stt.SpeechToText _speech;
  bool _initialised = false;

  /// BCP-47 tag the recogniser is asked for.
  static String localeId(Locale locale) => switch (locale.languageCode) {
    'te' => 'te_IN',
    'kn' => 'kn_IN',
    'hi' => 'hi_IN',
    'mr' => 'mr_IN',
    _ => 'en_IN',
  };

  Future<bool> _init() async {
    if (_initialised) return _speech.isAvailable;
    _initialised = true;
    try {
      return await _speech.initialize(onError: (_) {}, onStatus: (_) {});
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> isAvailable(Locale locale) => _init();

  @override
  Stream<SpeechResult> listen(Locale locale) {
    final controller = StreamController<SpeechResult>();
    unawaited(() async {
      if (!await _init()) {
        controller.addError(const SpeechUnavailable(SpeechFailure.unavailable));
        await controller.close();
        return;
      }
      try {
        await _speech.listen(
          onResult: (result) {
            if (controller.isClosed) return;
            controller.add(
              SpeechResult(result.recognizedWords, isFinal: result.finalResult),
            );
            if (result.finalResult) unawaited(controller.close());
          },
          listenOptions: stt.SpeechListenOptions(localeId: localeId(locale)),
        );
      } on Object {
        if (!controller.isClosed) {
          controller.addError(const SpeechUnavailable(SpeechFailure.error));
          await controller.close();
        }
      }
    }());
    return controller.stream;
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
