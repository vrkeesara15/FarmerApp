import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';

/// Copy for a blocking issue (A21 steps).
String issueText(CoreLocalizations l10n, StepIssue issue) => switch (issue) {
  StepIssue.nameRequired => l10n.regIssueName,
  StepIssue.phoneInvalid => l10n.phoneInvalid,
  StepIssue.phoneDuplicate => l10n.regDuplicatePhone,
  StepIssue.phoneUnverified => l10n.regIssuePhoneUnverified,
  StepIssue.villageRequired => l10n.regIssueVillage,
  StepIssue.languageRequired => l10n.regIssueLanguage,
  StepIssue.boundaryTooFewPoints => l10n.regIssueBoundary,
  StepIssue.boundarySelfIntersecting => l10n.regBoundaryInvalid,
  StepIssue.areaRequired => l10n.regIssueArea,
  StepIssue.cropRequired => l10n.regIssueCrop,
  StepIssue.sowingDateRequired => l10n.regIssueSowingDate,
  StepIssue.consentRequired => l10n.regIssueConsent,
};

/// Step title for the stepper.
String stepTitle(CoreLocalizations l10n, RegistrationStep step) =>
    switch (step) {
      RegistrationStep.basics => l10n.regStepBasics,
      RegistrationStep.boundary => l10n.regStepBoundary,
      RegistrationStep.crops => l10n.regStepCrops,
      RegistrationStep.consent => l10n.regStepConsent,
      RegistrationStep.review => l10n.regStepReview,
    };

/// OTP failure copy (A21a).
String? otpFailureText(CoreLocalizations l10n, RegistrationState s) =>
    switch (s.otpFailure) {
      OtpFailure.none => null,
      OtpFailure.invalidNumber => l10n.phoneInvalid,
      OtpFailure.wrongCode =>
        s.otpAttemptsLeft == null
            ? l10n.otpInvalid
            : '${l10n.otpInvalid} ${l10n.otpAttemptsLeft(s.otpAttemptsLeft!)}',
      OtpFailure.expired => l10n.otpExpired,
      OtpFailure.locked => l10n.otpLocked(
        ((s.otpRetryAfter?.inSeconds ?? 900) + 59) ~/ 60,
      ),
      OtpFailure.network => l10n.networkError,
    };

/// Localised crop name for the current locale.
String cropName(BuildContext context, CropRef crop) =>
    crop.nameIn(Localizations.localeOf(context).languageCode);

/// `DD-MM-YYYY` for a date-only value.
String formatDateDdMmYyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.year}';

/// Two-decimal acres.
String acresText(double acres) => acres.toStringAsFixed(2);

/// Section heading used across the wizard and the profile.
class SectionTitle extends StatelessWidget {
  /// Creates the heading.
  const SectionTitle(this.text, {this.trailing, super.key});

  /// Heading text.
  final String text;

  /// Optional trailing action.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.space4, bottom: Tokens.space2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text, style: app.text.heading)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Label + selectable chips for a small closed set (soil, irrigation, ...).
class ChoiceChips extends StatelessWidget {
  /// Creates the group.
  const ChoiceChips({
    required this.label,
    required this.values,
    required this.labelOf,
    required this.onSelected,
    this.selected,
    this.keyPrefix,
    this.iconOf,
    super.key,
  });

  /// Field label.
  final String label;

  /// Wire values in display order.
  final List<String> values;

  /// Localised label per value.
  final String Function(String value) labelOf;

  /// Optional icon per value.
  final IconData Function(String value)? iconOf;

  /// Current value.
  final String? selected;

  /// Tap handler.
  final ValueChanged<String> onSelected;

  /// Chips get `Key('<keyPrefix><value>')`.
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: app.text.label.copyWith(color: app.palette.textSecondary),
        ),
        const SizedBox(height: Tokens.space2),
        Wrap(
          spacing: Tokens.space2,
          runSpacing: Tokens.space2,
          children: <Widget>[
            for (final v in values)
              CropChip(
                key: keyPrefix == null ? null : Key('$keyPrefix$v'),
                data: CropChipData(
                  name: labelOf(v),
                  icon: iconOf?.call(v) ?? Icons.circle_outlined,
                ),
                selected: v == selected,
                onTap: () => onSelected(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// Tinted message box (warning / danger / info).
class NoticeBox extends StatelessWidget {
  /// Creates the box.
  const NoticeBox({
    required this.text,
    required this.color,
    required this.container,
    this.icon = Icons.info_outline,
    this.action,
    super.key,
  });

  /// Message.
  final String text;

  /// Foreground / border colour.
  final Color color;

  /// Background (tinted; plain surface in Sunlight).
  final Color container;

  /// Leading icon.
  final IconData icon;

  /// Optional action below the text.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Tokens.space3),
        decoration: BoxDecoration(
          color: app.tint(container),
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          border: Border.all(color: color, width: app.borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: color),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    text,
                    style: app.text.body.copyWith(color: color),
                  ),
                ),
              ],
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Key/value row for the review and profile screens.
class FactRow extends StatelessWidget {
  /// Creates the row.
  const FactRow({
    required this.label,
    required this.value,
    this.icon,
    super.key,
  });

  /// Label.
  final String label;

  /// Value (already localised).
  final String value;

  /// Optional leading icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: Tokens.sizeIcon, color: p.textSecondary),
            const SizedBox(width: Tokens.space2),
          ],
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: app.text.label.copyWith(color: p.textSecondary),
            ),
          ),
          const SizedBox(width: Tokens.space2),
          Expanded(child: Text(value, style: app.text.body)),
        ],
      ),
    );
  }
}

/// A text field whose controller follows an external value (draft) without
/// fighting the keyboard.
class DraftTextField extends StatefulWidget {
  /// Creates the field.
  const DraftTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.helperText,
    this.errorText,
    this.indiaPhone = false,
    this.keyboardType,
    this.prefixIcon,
    this.enabled = true,
    this.fieldKey,
    super.key,
  });

  /// Label above the input.
  final String label;

  /// Current value from the draft.
  final String value;

  /// Change handler.
  final ValueChanged<String> onChanged;

  /// Placeholder.
  final String? hintText;

  /// Helper.
  final String? helperText;

  /// Error.
  final String? errorText;

  /// `+91` mode.
  final bool indiaPhone;

  /// Keyboard.
  final TextInputType? keyboardType;

  /// Leading icon.
  final IconData? prefixIcon;

  /// Enabled.
  final bool enabled;

  /// Key on the inner `AppTextField` (tests).
  final Key? fieldKey;

  @override
  State<DraftTextField> createState() => _DraftTextFieldState();
}

class _DraftTextFieldState extends State<DraftTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(DraftTextField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(
    key: widget.fieldKey,
    label: widget.label,
    controller: _controller,
    hintText: widget.hintText,
    helperText: widget.helperText,
    errorText: widget.errorText,
    indiaPhone: widget.indiaPhone,
    keyboardType: widget.keyboardType,
    prefixIcon: widget.prefixIcon,
    enabled: widget.enabled,
    onChanged: widget.onChanged,
  );
}
