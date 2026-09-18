import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Six-box OTP entry with auto-advance and a resend timer
/// (SPEC 13.1 `OtpInput`).
///
/// A single hidden text field backs the six boxes so SMS autofill and paste
/// work; the highlighted box advances as digits are typed.
class OtpInput extends StatefulWidget {
  /// Creates the input.
  const OtpInput({
    this.length = 6,
    this.onCompleted,
    this.onChanged,
    this.onResend,
    this.resendAfter = const Duration(seconds: 30),
    this.errorText,
    this.autofocus = true,
    this.enabled = true,
    super.key,
  });

  /// Number of digits.
  final int length;

  /// Called once all digits are entered.
  final ValueChanged<String>? onCompleted;

  /// Called on every change.
  final ValueChanged<String>? onChanged;

  /// Called when the user taps "Resend OTP". Restarts the timer.
  final VoidCallback? onResend;

  /// How long to wait before resend is allowed.
  final Duration resendAfter;

  /// Error shown under the boxes.
  final String? errorText;

  /// Focus on mount.
  final bool autofocus;

  /// Whether typing is allowed.
  final bool enabled;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _timer;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _remaining = widget.resendAfter.inSeconds;
    if (_remaining <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _remaining -= 1;
        if (_remaining <= 0) t.cancel();
      });
    });
  }

  void _onText() {
    final value = _controller.text;
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      widget.onCompleted?.call(value);
    }
    setState(() {});
  }

  void _resend() {
    widget.onResend?.call();
    _controller.clear();
    setState(_startTimer);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller
      ..removeListener(_onText)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final value = _controller.text;
    final active = value.length.clamp(0, widget.length - 1);
    final hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l10n.otpLabel,
          style: app.text.label.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: Tokens.space2),
        Stack(
          children: <Widget>[
            // Hidden field that owns the text and keyboard.
            Opacity(
              opacity: 0,
              child: SizedBox(
                height: Tokens.sizePrimaryButtonHeight,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  showCursor: false,
                  decoration: const InputDecoration.collapsed(hintText: ''),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled ? _focus.requestFocus : null,
              child: Row(
                children: <Widget>[
                  for (var i = 0; i < widget.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: Tokens.space2),
                    Expanded(
                      child: _OtpBox(
                        digit: i < value.length ? value[i] : '',
                        active:
                            widget.enabled && i == active && _focus.hasFocus,
                        error: hasError,
                        semanticsLabel: l10n.otpDigitLabel(i + 1),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          Row(
            children: <Widget>[
              Icon(Icons.error_outline, color: p.statusDanger),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: app.text.caption.copyWith(color: p.statusDanger),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Tokens.space3),
        if (_remaining > 0)
          Row(
            children: <Widget>[
              Icon(Icons.timer_outlined, color: p.textSecondary),
              const SizedBox(width: Tokens.space2),
              Text(
                l10n.otpResendIn(_remaining),
                style: app.text.body.copyWith(color: p.textSecondary),
              ),
            ],
          )
        else
          Semantics(
            button: true,
            child: TextButton.icon(
              onPressed: widget.enabled ? _resend : null,
              style: TextButton.styleFrom(
                foregroundColor: p.primary,
                minimumSize: const Size(
                  Tokens.sizeTouchTargetMin,
                  Tokens.sizeTouchTargetMin,
                ),
                textStyle: app.text.label,
              ),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.otpResend),
            ),
          ),
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.digit,
    required this.active,
    required this.error,
    required this.semanticsLabel,
  });

  final String digit;
  final bool active;
  final bool error;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final color = error
        ? p.statusDanger
        : active
        ? p.primary
        : p.border;
    return Semantics(
      label: semanticsLabel,
      value: digit,
      child: Container(
        height: Tokens.sizePrimaryButtonHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusInput),
          border: Border.all(
            color: color,
            width: active ? app.borderWidth + 1 : app.borderWidth,
          ),
        ),
        child: Text(digit, style: app.text.title),
      ),
    );
  }
}
