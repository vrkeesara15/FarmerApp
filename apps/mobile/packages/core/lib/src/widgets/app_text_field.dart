import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Text input with a visible label above, helper text and error state
/// (SPEC 13.1 `AppTextField`).
///
/// Set [indiaPhone] to render the fixed `+91` prefix, a numeric keyboard and a
/// 10-digit limit.
class AppTextField extends StatelessWidget {
  /// Creates the field.
  const AppTextField({
    required this.label,
    this.controller,
    this.helperText,
    this.errorText,
    this.hintText,
    this.indiaPhone = false,
    this.enabled = true,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    super.key,
  });

  /// Label shown above the input. Always visible (not a floating placeholder).
  final String label;

  /// Optional controller.
  final TextEditingController? controller;

  /// Helper text under the input.
  final String? helperText;

  /// Error text under the input; also turns the border red.
  final String? errorText;

  /// Placeholder inside the input.
  final String? hintText;

  /// Indian mobile mode: `+91` prefix, digits only, 10 characters.
  final bool indiaPhone;

  /// Whether the field accepts input.
  final bool enabled;

  /// Focus on mount.
  final bool autofocus;

  /// Keyboard type (ignored when [indiaPhone]).
  final TextInputType? keyboardType;

  /// Keyboard action.
  final TextInputAction? textInputAction;

  /// Maximum length (10 when [indiaPhone]).
  final int? maxLength;

  /// Lines the input grows to (notes fields pass 3).
  final int maxLines;

  /// Change callback.
  final ValueChanged<String>? onChanged;

  /// Submit callback.
  final ValueChanged<String>? onSubmitted;

  /// Optional leading icon.
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final effectiveMax = indiaPhone ? 10 : maxLength;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: app.text.label.copyWith(
            color: enabled ? p.textSecondary : p.textMuted,
          ),
        ),
        const SizedBox(height: Tokens.space2),
        TextField(
          controller: controller,
          enabled: enabled,
          autofocus: autofocus,
          keyboardType: indiaPhone ? TextInputType.phone : keyboardType,
          textInputAction: textInputAction,
          maxLength: effectiveMax,
          maxLines: indiaPhone ? 1 : maxLines,
          inputFormatters: indiaPhone
              ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
              : null,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: app.text.body,
          decoration: InputDecoration(
            hintText: hintText,
            helperText: helperText,
            helperMaxLines: 2,
            errorText: errorText,
            errorMaxLines: 2,
            counterText: '',
            prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
            prefixText: indiaPhone ? '${l10n.phonePrefix} ' : null,
            prefixStyle: app.text.body,
            constraints: const BoxConstraints(
              minHeight: Tokens.sizePrimaryButtonHeight,
            ),
          ),
        ),
      ],
    );
  }
}
