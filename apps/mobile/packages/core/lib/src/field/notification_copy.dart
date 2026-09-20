import '../i18n/generated/core_localizations.dart';
import 'field_models.dart';

/// Renders a server notification row in the app's own language (FA-007).
///
/// The server never sends display text: every row carries `title_key` and
/// `body_key` (e.g. `notification.beat_plan_ready.title`,
/// `notification.travel_claim_decided.body.approved`) plus the ids. An app
/// that does not know a kind falls back to a generic line and the `/inbox`
/// route, so a new server kind never shows a blank card.
abstract final class NotificationCopy {
  /// Title for [item].
  static String title(CoreLocalizations l10n, InboxItem item) =>
      switch (item.kind) {
        'beat_plan_ready' => l10n.notifBeatPlanReadyTitle,
        'order_status' => l10n.notifOrderStatusTitle,
        'credit_approval_decided' => l10n.notifCreditApprovalTitle,
        'travel_claim_submitted' => l10n.notifTravelClaimSubmittedTitle,
        'travel_claim_decided' => l10n.notifTravelClaimDecidedTitle,
        'flag_assigned' || 'flag_escalated' => l10n.notifFlagTitle,
        'duty_auto_ended' => l10n.dutyEndedTitle,
        'diagnosis_ready' ||
        'diagnosis_reviewed' ||
        'diagnosis_expert_requested' => l10n.notifDiagnosisTitle,
        'visit_confirm_request' => l10n.notifVisitConfirmTitle,
        _ => l10n.notifGenericTitle,
      };

  /// Body for [item]; the `.approved` / `.rejected` suffix of the server's
  /// body key picks the variant.
  static String body(CoreLocalizations l10n, InboxItem item) {
    final approved = item.bodyKey.endsWith('.approved');
    return switch (item.kind) {
      'beat_plan_ready' => l10n.notifBeatPlanReadyBody,
      'order_status' => l10n.notifOrderStatusBody,
      'credit_approval_decided' =>
        approved
            ? l10n.notifCreditApprovalApproved
            : l10n.notifCreditApprovalRejected,
      'travel_claim_submitted' => l10n.notifTravelClaimSubmittedBody,
      'travel_claim_decided' =>
        approved
            ? l10n.notifTravelClaimApproved
            : l10n.notifTravelClaimRejected,
      'flag_assigned' || 'flag_escalated' => l10n.notifFlagBody,
      'duty_auto_ended' => l10n.notifDutyAutoEndedBody,
      'diagnosis_ready' ||
      'diagnosis_reviewed' ||
      'diagnosis_expert_requested' => l10n.notifDiagnosisBody,
      'visit_confirm_request' => l10n.notifVisitConfirmBody,
      _ => l10n.notifGenericBody,
    };
  }
}
