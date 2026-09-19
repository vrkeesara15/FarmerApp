import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/generated/core_localizations.dart';
import '../kisan/audio_prompt.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Speaker button next to a key farmer instruction (NF-009): icon paired
/// with a text label, 48 dp target. Plays [text] through
/// [audioPromptProvider] in the current language. When the device has no
/// voice for the language the button turns into a disabled "Audio
/// unavailable" state instead of failing silently.
class AudioButton extends ConsumerStatefulWidget {
  /// Creates the button.
  const AudioButton({
    required this.promptId,
    required this.text,
    this.label,
    this.locale,
    super.key,
  });

  /// Prompt name (recorded clip file name once clips exist).
  final String promptId;

  /// What is spoken.
  final String text;

  /// Visible label; defaults to "Listen".
  final String? label;

  /// Language; defaults to the app's current locale.
  final Locale? locale;

  @override
  ConsumerState<AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends ConsumerState<AudioButton> {
  bool? _available;
  Locale? _checked;

  Locale get _locale => widget.locale ?? Localizations.localeOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = _locale;
    if (locale != _checked) {
      _checked = locale;
      _check(locale);
    }
  }

  Future<void> _check(Locale locale) async {
    final ok = await ref.read(audioPromptProvider).isAvailable(locale);
    if (mounted && _checked == locale) setState(() => _available = ok);
  }

  Future<void> _play() async {
    final result = await ref
        .read(audioPromptProvider)
        .play(promptId: widget.promptId, text: widget.text, locale: _locale);
    if (!mounted) return;
    if (result == AudioPlayResult.unavailable) {
      setState(() => _available = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final unavailable = _available == false;
    return Semantics(
      button: true,
      enabled: !unavailable,
      label: unavailable
          ? l10n.audioUnavailable
          : widget.label ?? l10n.audioListen,
      excludeSemantics: true,
      child: TextButton(
        key: Key('audio-${widget.promptId}'),
        onPressed: unavailable ? null : _play,
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          disabledForegroundColor: p.textSecondary,
          minimumSize: const Size(
            Tokens.sizeTouchTargetMin,
            Tokens.sizeTouchTargetMin,
          ),
          textStyle: app.text.label,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              unavailable
                  ? Icons.volume_off_outlined
                  : Icons.volume_up_outlined,
            ),
            const SizedBox(width: Tokens.space2),
            Flexible(
              child: Text(
                unavailable
                    ? l10n.audioUnavailable
                    : widget.label ?? l10n.audioListen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
