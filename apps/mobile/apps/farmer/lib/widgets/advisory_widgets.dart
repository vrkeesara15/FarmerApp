import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';

/// Shared pictograms and copy for the M7 farmer screens: the crop
/// calendar (F42), the weather (F43), the district alerts (F44) and the
/// notification inbox (FA-007). Every icon is paired with text (NF-009).

/// Pictogram for a calendar task type.
IconData taskTypeIcon(String taskType) => switch (taskType) {
  TaskTypes.sow => Icons.grass,
  TaskTypes.irrigate => Icons.water_drop_outlined,
  TaskTypes.fertilise => Icons.science_outlined,
  TaskTypes.spray => Icons.sanitizer_outlined,
  TaskTypes.harvest => Icons.agriculture,
  _ => Icons.checklist_outlined,
};

/// Localised label of a task type.
String taskTypeLabel(CoreLocalizations l10n, String taskType) =>
    switch (taskType) {
      TaskTypes.sow => l10n.taskTypeSow,
      TaskTypes.irrigate => l10n.taskTypeIrrigate,
      TaskTypes.fertilise => l10n.taskTypeFertilise,
      TaskTypes.spray => l10n.taskTypeSpray,
      TaskTypes.harvest => l10n.taskTypeHarvest,
      _ => taskType,
    };

/// Pictogram for a WMO weather code (Open-Meteo).
IconData weatherIcon(int code) {
  if (code >= 95) return Icons.thunderstorm_outlined;
  if (code >= 80) return Icons.grain;
  if (code >= 71) return Icons.ac_unit;
  if (code >= 61) return Icons.umbrella_outlined;
  if (code >= 51) return Icons.water_drop_outlined;
  if (code >= 45) return Icons.foggy;
  if (code >= 2) return Icons.cloud_outlined;
  return Icons.wb_sunny_outlined;
}

/// Localised sky description for a WMO weather code.
String weatherSky(CoreLocalizations l10n, int code) {
  if (code >= 95) return l10n.weatherSkyThunder;
  if (code >= 80) return l10n.weatherSkyShowers;
  if (code >= 71) return l10n.weatherSkyFog;
  if (code >= 61) return l10n.weatherSkyRain;
  if (code >= 51) return l10n.weatherSkyDrizzle;
  if (code >= 45) return l10n.weatherSkyFog;
  if (code >= 2) return l10n.weatherSkyCloudy;
  return l10n.weatherSkyClear;
}

/// Localised reason a spray window is bad (i18n keys from the API).
String sprayReason(CoreLocalizations l10n, String code) => switch (code) {
  SprayReasons.rainLikely => l10n.weatherReasonRainLikely,
  SprayReasons.rain => l10n.weatherReasonRain,
  SprayReasons.windHigh => l10n.weatherReasonWindHigh,
  _ => code,
};

/// Localised caution on a spray window.
String sprayCaution(CoreLocalizations l10n, String code) => switch (code) {
  'heat' => l10n.weatherCautionHeat,
  'humidity_high' => l10n.weatherCautionHumidityHigh,
  'humidity_low' => l10n.weatherCautionHumidityLow,
  _ => code,
};

/// Localised label of a derived alert severity.
String alertSeverityLabel(CoreLocalizations l10n, AlertSeverity severity) =>
    switch (severity) {
      AlertSeverity.high => l10n.alertSeverityHigh,
      AlertSeverity.medium => l10n.alertSeverityMedium,
      AlertSeverity.low => l10n.alertSeverityLow,
    };

/// F44 "what to look for": a short checklist for the problem type. The
/// API has no per-problem symptom list yet (follow-up in
/// docs/prs/M7-farmer-mobile.md), so the list is by `problem_type` and
/// always ends with "walk your field".
List<String> alertSymptoms(CoreLocalizations l10n, String problemType) =>
    switch (problemType) {
      'pest' => <String>[
        l10n.alertSignPestUnderLeaf,
        l10n.alertSignPestHoles,
        l10n.alertSignPestWilting,
        l10n.alertSignWalkField,
      ],
      'disease' => <String>[
        l10n.alertSignDiseaseSpots,
        l10n.alertSignDiseasePowder,
        l10n.alertSignDiseaseRot,
        l10n.alertSignWalkField,
      ],
      'deficiency' => <String>[
        l10n.alertSignDeficiencyColour,
        l10n.alertSignDeficiencyGrowth,
        l10n.alertSignWalkField,
      ],
      'weed' => <String>[l10n.alertSignWeedPatches, l10n.alertSignWalkField],
      _ => <String>[l10n.alertSignWalkField],
    };

/// Title and body of an inbox row. The server sends i18n keys only
/// (FA-007: no text from the server), so the app resolves them here and
/// falls back to a generic line for a kind it does not know yet.
(String, String) notificationCopy(
  CoreLocalizations l10n,
  AppNotification notification,
) => switch (notification.kind) {
  NotificationKinds.diagnosisReady => (
    l10n.notifDiagnosisReadyTitle,
    l10n.notifDiagnosisReadyBody,
  ),
  NotificationKinds.diagnosisReviewed => (
    l10n.notifDiagnosisReviewedTitle,
    l10n.notifDiagnosisReviewedBody,
  ),
  NotificationKinds.diagnosisExpertRequested => (
    l10n.notifDiagnosisExpertTitle,
    l10n.notifDiagnosisExpertBody,
  ),
  NotificationKinds.orderStatus => (
    l10n.farmerNotifOrderStatusTitle,
    l10n.farmerNotifOrderStatusBody,
  ),
  NotificationKinds.outbreakAlert => (
    l10n.notifOutbreakAlertTitle,
    l10n.notifOutbreakAlertBody,
  ),
  NotificationKinds.cropTaskReminder => (
    l10n.notifCropTaskReminderTitle,
    l10n.notifCropTaskReminderBody,
  ),
  NotificationKinds.visitConfirmRequest => (
    l10n.farmerNotifVisitConfirmTitle,
    l10n.farmerNotifVisitConfirmBody,
  ),
  _ => (l10n.farmerNotifGenericTitle, l10n.farmerNotifGenericBody),
};

/// Pictogram of an inbox row.
IconData notificationIcon(String kind) => switch (kind) {
  NotificationKinds.diagnosisReady ||
  NotificationKinds.diagnosisReviewed ||
  NotificationKinds.diagnosisExpertRequested => Icons.eco_outlined,
  NotificationKinds.orderStatus => Icons.shopping_bag_outlined,
  NotificationKinds.outbreakAlert => Icons.warning_amber_outlined,
  NotificationKinds.cropTaskReminder => Icons.event_available_outlined,
  NotificationKinds.visitConfirmRequest => Icons.how_to_reg_outlined,
  _ => Icons.notifications_none,
};

/// A coloured severity chip, icon paired with the word (NF-009).
class SeverityChip extends StatelessWidget {
  /// Creates the chip.
  const SeverityChip(this.severity, {super.key});

  /// The derived severity.
  final AlertSeverity severity;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final p = app.palette;
    final colour = switch (severity) {
      AlertSeverity.high => p.statusDanger,
      AlertSeverity.medium => p.statusWarning,
      AlertSeverity.low => p.textSecondary,
    };
    final icon = switch (severity) {
      AlertSeverity.high => Icons.priority_high,
      AlertSeverity.medium => Icons.error_outline,
      AlertSeverity.low => Icons.info_outline,
    };
    return Chip(
      key: Key('severity-${severity.name}'),
      avatar: Icon(icon, size: Tokens.space4 + 2, color: colour),
      label: Text(
        alertSeverityLabel(l10n, severity),
        style: app.text.label.copyWith(color: colour),
      ),
      side: BorderSide(color: colour),
    );
  }
}
