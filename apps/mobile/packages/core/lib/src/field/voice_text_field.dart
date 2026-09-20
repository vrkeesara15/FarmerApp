import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../widgets/app_text_field.dart';
import 'field_providers.dart';
import 'speech_service.dart';

/// FA-005: a free-text field with a microphone next to it.
///
/// Dictation is an accelerator, never a requirement — the keyboard always
/// works, and on a device without a speech service the microphone shows a
/// one-line explanation instead of failing silently. Recognised text is
/// appended to whatever is already in the field, so the officer can dictate
/// a sentence, fix a word and dictate again.
class VoiceTextField extends ConsumerStatefulWidget {
  /// Creates the field.
  const VoiceTextField({
    required this.label,
    required this.controller,
    this.hintText,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.fieldKey,
    this.micKey,
    super.key,
  });

  /// Label above the input.
  final String label;

  /// The text being edited.
  final TextEditingController controller;

  /// Placeholder.
  final String? hintText;

  /// Helper text under the input.
  final String? helperText;

  /// Error text under the input.
  final String? errorText;

  /// Whether the field (and the microphone) accept input.
  final bool enabled;

  /// Lines the input grows to.
  final int maxLines;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Change callback (also fired after dictation).
  final ValueChanged<String>? onChanged;

  /// Key of the text input (tests type into this).
  final Key? fieldKey;

  /// Key of the microphone button.
  final Key? micKey;

  @override
  ConsumerState<VoiceTextField> createState() => _VoiceTextFieldState();
}

class _VoiceTextFieldState extends ConsumerState<VoiceTextField> {
  StreamSubscription<SpeechResult>? _sub;
  String _partial = '';
  bool _listening = false;
  bool _unavailable = false;
  String _base = '';

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }

  Locale get _locale => Localizations.localeOf(context);

  void _commit(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final next = _base.isEmpty ? trimmed : '${_base.trimRight()} $trimmed';
    widget.controller
      ..text = next
      ..selection = TextSelection.collapsed(offset: next.length);
    widget.onChanged?.call(next);
  }

  Future<void> _stop() async {
    await ref.read(speechServiceProvider).stop();
    await _sub?.cancel();
    _sub = null;
    if (_partial.isNotEmpty) _commit(_partial);
    if (mounted) {
      setState(() {
        _listening = false;
        _partial = '';
      });
    }
  }

  Future<void> _start() async {
    final speech = ref.read(speechServiceProvider);
    final locale = _locale;
    if (!await speech.isAvailable(locale)) {
      if (mounted) setState(() => _unavailable = true);
      return;
    }
    _base = widget.controller.text;
    setState(() {
      _listening = true;
      _unavailable = false;
      _partial = '';
    });
    _sub = speech
        .listen(locale)
        .listen(
          (result) {
            if (!mounted) return;
            if (result.isFinal) {
              _commit(result.text);
              setState(() {
                _listening = false;
                _partial = '';
              });
              unawaited(_sub?.cancel());
              _sub = null;
            } else {
              setState(() => _partial = result.text);
            }
          },
          onError: (Object _) {
            if (!mounted) return;
            setState(() {
              _listening = false;
              _partial = '';
              _unavailable = true;
            });
          },
          onDone: () {
            if (!mounted || !_listening) return;
            if (_partial.isNotEmpty) _commit(_partial);
            setState(() {
              _listening = false;
              _partial = '';
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: AppTextField(
                key: widget.fieldKey,
                label: widget.label,
                hintText: widget.hintText,
                helperText: widget.helperText,
                errorText: widget.errorText,
                controller: widget.controller,
                enabled: widget.enabled,
                maxLines: widget.maxLines,
                keyboardType: widget.keyboardType,
                onChanged: widget.onChanged,
              ),
            ),
            const SizedBox(width: Tokens.space2),
            Padding(
              padding: const EdgeInsets.only(top: Tokens.space6),
              child: IconButton(
                key: widget.micKey,
                icon: Icon(
                  _listening
                      ? Icons.stop_circle_outlined
                      : Icons.mic_none_outlined,
                  color: _listening ? p.statusDanger : p.primary,
                ),
                tooltip: _listening ? l10n.voiceStop : l10n.voiceStart,
                onPressed: widget.enabled
                    ? () => unawaited(_listening ? _stop() : _start())
                    : null,
              ),
            ),
          ],
        ),
        if (_listening)
          Padding(
            key: const Key('voice-listening'),
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Row(
              children: <Widget>[
                Icon(Icons.graphic_eq, size: 16, color: p.statusDanger),
                const SizedBox(width: Tokens.space1),
                Expanded(
                  child: Text(
                    _partial.isEmpty ? l10n.voiceListening : _partial,
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        if (_unavailable)
          Padding(
            key: const Key('voice-unavailable'),
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Text(
              l10n.voiceUnavailable,
              style: app.text.caption.copyWith(color: p.textSecondary),
            ),
          ),
      ],
    );
  }
}
