import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What happened when a prompt was asked to play (NF-009).
enum AudioPlayResult {
  /// The prompt is playing (or was played).
  played,

  /// No voice for the language on this device: the button shows
  /// "audio unavailable".
  unavailable,
}

/// Plays the short spoken prompts next to key farmer instructions
/// (FM-001 F01, FM-002 F04, NF-009).
///
/// The farmer app implements it with the device's text-to-speech voice for
/// the locale (`TtsAudioPrompt`); recorded clips by native speakers (human
/// gate, SPEC NF-008) replace TTS behind this same interface later: a
/// clip-backed implementation plays `assets/audio/<lang>/<promptId>.ogg`
/// and ignores [text].
abstract interface class AudioPrompt {
  /// Whether a voice for [locale] exists on this device.
  Future<bool> isAvailable(Locale locale);

  /// Speaks [text] in [locale]. [promptId] names the prompt (the recorded
  /// clip's file name once clips exist).
  Future<AudioPlayResult> play({
    required String promptId,
    required String text,
    required Locale locale,
  });

  /// Stops anything playing.
  Future<void> stop();
}

/// Never plays (no TTS engine at all).
class SilentAudioPrompt implements AudioPrompt {
  /// Creates the prompt.
  const SilentAudioPrompt();

  @override
  Future<bool> isAvailable(Locale locale) async => false;

  @override
  Future<AudioPlayResult> play({
    required String promptId,
    required String text,
    required Locale locale,
  }) async => AudioPlayResult.unavailable;

  @override
  Future<void> stop() async {}
}

/// One recorded [FakeAudioPrompt.play] call.
class PlayedPrompt {
  /// Creates the record.
  const PlayedPrompt(this.promptId, this.text, this.locale);

  /// Prompt id.
  final String promptId;

  /// Text that would be spoken.
  final String text;

  /// Language.
  final Locale locale;
}

/// Records prompts (tests, previews). Languages in [unavailable] have no
/// voice.
class FakeAudioPrompt implements AudioPrompt {
  /// Creates the fake.
  FakeAudioPrompt({Set<String>? unavailable})
    : unavailable = unavailable ?? <String>{};

  /// Language codes without a voice.
  final Set<String> unavailable;

  /// Prompts played, in order.
  final List<PlayedPrompt> played = <PlayedPrompt>[];

  /// Stop calls.
  int stops = 0;

  @override
  Future<bool> isAvailable(Locale locale) async =>
      !unavailable.contains(locale.languageCode);

  @override
  Future<AudioPlayResult> play({
    required String promptId,
    required String text,
    required Locale locale,
  }) async {
    if (unavailable.contains(locale.languageCode)) {
      return AudioPlayResult.unavailable;
    }
    played.add(PlayedPrompt(promptId, text, locale));
    return AudioPlayResult.played;
  }

  @override
  Future<void> stop() async => stops += 1;
}

/// The prompt player; the farmer app overrides it with `TtsAudioPrompt`.
final Provider<AudioPrompt> audioPromptProvider = Provider<AudioPrompt>(
  (ref) => FakeAudioPrompt(),
);
