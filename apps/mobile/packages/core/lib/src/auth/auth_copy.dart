import '../i18n/generated/core_localizations.dart';
import '../state/auth_flow.dart';

/// Localised copy for an [AuthFlowState] failure (A03/A04, F02/F03).
///
/// Returns `null` when there is nothing to show.
String? authFailureText(CoreLocalizations l10n, AuthFlowState flow) {
  return switch (flow.failure) {
    AuthFailure.none => null,
    AuthFailure.invalidNumber => l10n.phoneInvalid,
    AuthFailure.notFound => l10n.phoneNotFound,
    AuthFailure.rateLimited => l10n.otpRateLimited(flow.retryAfterMinutes),
    AuthFailure.locked => l10n.otpLocked(flow.retryAfterMinutes),
    AuthFailure.wrongCode => switch (flow.attemptsLeft) {
      final int left => '${l10n.otpInvalid} ${l10n.otpAttemptsLeft(left)}',
      null => l10n.otpInvalid,
    },
    AuthFailure.expired => l10n.otpExpired,
    AuthFailure.deviceNotBound => l10n.loginDeviceNotBound,
    AuthFailure.network => l10n.networkError,
  };
}
