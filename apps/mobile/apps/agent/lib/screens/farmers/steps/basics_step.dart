import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../wizard_copy.dart';

/// A21a: name, phone with OTP to the farmer (or "verify later" offline),
/// village, landmark, preferred language, land ownership.
class BasicsStep extends ConsumerWidget {
  /// Creates the step.
  const BasicsStep({this.showIssues = false, super.key});

  /// Show validation errors (after a failed Next).
  final bool showIssues;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(registrationProvider);
    final wizard = ref.read(registrationProvider.notifier);
    final draft = state.draft!;
    final issues = showIssues
        ? wizard.issuesFor(RegistrationStep.basics)
        : const <StepIssue>[];
    final villages = ref.watch(villagesProvider).value ?? const <Village>[];
    final offline = ref.watch(offlineProvider);
    final duplicate = state.duplicateOfId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DraftTextField(
          fieldKey: const Key('reg-name'),
          label: l10n.regNameLabel,
          value: draft.name,
          hintText: l10n.regNameHint,
          prefixIcon: Icons.person_outline,
          errorText: issues.contains(StepIssue.nameRequired)
              ? l10n.regIssueName
              : null,
          onChanged: (v) => unawaited(wizard.setName(v)),
        ),
        const SizedBox(height: Tokens.space4),
        DraftTextField(
          fieldKey: const Key('reg-phone'),
          label: l10n.regPhoneLabel,
          value: draft.phone,
          indiaPhone: true,
          helperText: l10n.regPhoneHelper,
          errorText: duplicate != null
              ? l10n.regDuplicatePhone
              : issues.contains(StepIssue.phoneInvalid)
              ? l10n.phoneInvalid
              : null,
          onChanged: (v) => unawaited(wizard.setPhone(v)),
        ),
        if (duplicate != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              key: const Key('reg-open-duplicate'),
              label: l10n.regDuplicateOpen,
              variant: AppButtonVariant.tertiary,
              size: AppButtonSize.medium,
              expand: false,
              icon: Icons.open_in_new,
              onPressed: () => context.push(AppRoutes.farmerPath(duplicate)),
            ),
          ),
        const SizedBox(height: Tokens.space3),
        _VerificationBlock(
          state: state,
          offline: offline,
          showIssue: issues.contains(StepIssue.phoneUnverified),
        ),
        const SizedBox(height: Tokens.space4),
        if (villages.isNotEmpty)
          _VillagePicker(
            villages: villages,
            selected: draft.villageId,
            errorText: issues.contains(StepIssue.villageRequired)
                ? l10n.regIssueVillage
                : null,
            onSelected: (v) =>
                unawaited(wizard.setVillage(v?.id, name: v?.name ?? '')),
          )
        else
          DraftTextField(
            fieldKey: const Key('reg-village-name'),
            label: l10n.regVillageTyped,
            value: draft.villageName,
            helperText: l10n.regVillageNoneSynced,
            prefixIcon: Icons.place_outlined,
            errorText: issues.contains(StepIssue.villageRequired)
                ? l10n.regIssueVillage
                : null,
            onChanged: (v) => unawaited(wizard.setVillageName(v)),
          ),
        const SizedBox(height: Tokens.space4),
        DraftTextField(
          fieldKey: const Key('reg-landmark'),
          label: l10n.regLandmarkLabel,
          value: draft.landmark,
          hintText: l10n.regLandmarkHint,
          prefixIcon: Icons.flag_outlined,
          onChanged: (v) => unawaited(wizard.setLandmark(v)),
        ),
        const SizedBox(height: Tokens.space4),
        Text(
          l10n.regLanguageLabel,
          style: app.text.label.copyWith(
            color: issues.contains(StepIssue.languageRequired)
                ? p.statusDanger
                : p.textSecondary,
          ),
        ),
        const SizedBox(height: Tokens.space2),
        LanguagePicker.compact(
          keyPrefix: 'reg-lang-',
          selected: draft.language == null ? null : Locale(draft.language!),
          onSelected: (locale) =>
              unawaited(wizard.setLanguage(locale.languageCode)),
        ),
        if (issues.contains(StepIssue.languageRequired)) ...<Widget>[
          const SizedBox(height: Tokens.space1),
          Text(
            l10n.regIssueLanguage,
            style: app.text.caption.copyWith(color: p.statusDanger),
          ),
        ],
        const SizedBox(height: Tokens.space4),
        ChoiceChips(
          label: l10n.regOwnershipLabel,
          keyPrefix: 'reg-own-',
          values: LandOwnershipTypes.values,
          labelOf: (v) => LandOwnershipTypes.label(l10n, v),
          iconOf: (v) => v == LandOwnershipTypes.own
              ? Icons.home_outlined
              : Icons.handshake_outlined,
          selected: draft.landOwnership,
          onSelected: (v) => unawaited(wizard.setLandOwnership(v)),
        ),
      ],
    );
  }
}

class _VerificationBlock extends ConsumerWidget {
  const _VerificationBlock({
    required this.state,
    required this.offline,
    required this.showIssue,
  });

  final RegistrationState state;
  final bool offline;
  final bool showIssue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final wizard = ref.read(registrationProvider.notifier);
    final draft = state.draft!;
    final failure = otpFailureText(l10n, state);
    final canSend =
        indianMobilePattern.hasMatch(draft.phone) &&
        state.duplicateOfId == null &&
        state.otp == OtpUiState.idle;

    switch (draft.verification) {
      case PhoneVerification.verified:
        return Row(
          key: const Key('reg-phone-verified'),
          children: <Widget>[
            Icon(Icons.verified_outlined, color: p.statusSuccess),
            const SizedBox(width: Tokens.space2),
            Text(
              l10n.regPhoneVerified,
              style: app.text.label.copyWith(color: p.statusSuccess),
            ),
          ],
        );
      case PhoneVerification.verifyLater:
        return Row(
          key: const Key('reg-verify-later-chosen'),
          children: <Widget>[
            Icon(Icons.schedule_outlined, color: p.statusWarning),
            const SizedBox(width: Tokens.space2),
            Expanded(
              child: Text(
                l10n.regVerifyLaterChosen,
                style: app.text.label.copyWith(color: p.statusWarning),
              ),
            ),
            AppButton(
              key: const Key('reg-send-otp'),
              label: l10n.regSendOtpToFarmer,
              variant: AppButtonVariant.tertiary,
              size: AppButtonSize.medium,
              expand: false,
              onPressed: canSend && !offline ? wizard.sendOtp : null,
            ),
          ],
        );
      case PhoneVerification.unverified:
      case PhoneVerification.sent:
        final sent = draft.verification == PhoneVerification.sent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!sent)
              AppButton(
                key: const Key('reg-send-otp'),
                label: l10n.regSendOtpToFarmer,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                icon: Icons.sms_outlined,
                loading: state.otp == OtpUiState.sending,
                onPressed: canSend ? wizard.sendOtp : null,
              ),
            if (sent) ...<Widget>[
              Text(
                l10n.regOtpSent,
                style: app.text.body.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: Tokens.space2),
              OtpInput(
                autofocus: false,
                enabled:
                    state.otp == OtpUiState.idle &&
                    state.otpFailure != OtpFailure.locked,
                errorText: failure,
                onCompleted: (code) => unawaited(wizard.confirmOtp(code)),
                onResend: () => unawaited(wizard.sendOtp()),
              ),
            ],
            if (!sent && failure != null) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              Text(
                failure,
                style: app.text.caption.copyWith(color: p.statusDanger),
              ),
            ],
            if (showIssue) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              Text(
                l10n.regIssuePhoneUnverified,
                style: app.text.caption.copyWith(color: p.statusDanger),
              ),
            ],
            if (offline || state.otpFailure == OtpFailure.network) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              NoticeBox(
                text: l10n.regVerifyLaterNote,
                icon: Icons.cloud_off_outlined,
                color: p.statusWarning,
                container: p.statusWarningContainer,
                action: AppButton(
                  key: const Key('reg-verify-later'),
                  label: l10n.regVerifyLater,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  icon: Icons.schedule_outlined,
                  onPressed: indianMobilePattern.hasMatch(draft.phone)
                      ? wizard.verifyLater
                      : null,
                ),
              ),
            ],
          ],
        );
    }
  }
}

class _VillagePicker extends StatelessWidget {
  const _VillagePicker({
    required this.villages,
    required this.selected,
    required this.onSelected,
    this.errorText,
  });

  final List<Village> villages;
  final String? selected;
  final String? errorText;
  final ValueChanged<Village?> onSelected;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.regVillageLabel,
          style: app.text.label.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: Tokens.space2),
        DropdownButtonFormField<String>(
          key: const Key('reg-village'),
          isExpanded: true,
          initialValue: selected,
          hint: Text(l10n.regVillageHint),
          style: app.text.body,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.place_outlined),
            errorText: errorText,
          ),
          items: <DropdownMenuItem<String>>[
            for (final v in villages)
              DropdownMenuItem<String>(
                key: Key('reg-village-${v.id}'),
                value: v.id,
                child: Text(
                  v.mandal.isEmpty ? v.name : '${v.name} · ${v.mandal}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) =>
              onSelected(villages.where((v) => v.id == id).firstOrNull),
        ),
      ],
    );
  }
}
