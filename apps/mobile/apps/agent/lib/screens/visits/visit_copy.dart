import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';

/// Visit routes (SPEC 13.2 A30–A34).
abstract final class VisitRoutes {
  /// A34 Visits list.
  static const String list = '/visits';

  /// A30 Start visit (optionally for a farmer / farm from A22).
  static String start({String? farmerId, String? farmId}) {
    final q = <String, String>{'farmerId': ?farmerId, 'farmId': ?farmId};
    return Uri(
      path: '/visits/new',
      queryParameters: q.isEmpty ? null : q,
    ).toString();
  }

  /// A31 Visit in progress.
  static String visit(String id) => '/visits/$id';

  /// A32 Farmer confirmation.
  static String confirm(String id) => '/visits/$id/confirm';

  /// A33 Check-out summary.
  static String summary(String id) => '/visits/$id/summary';
}

/// Localised label of a confirmation channel wire value.
String channelLabel(CoreLocalizations l10n, String channel) =>
    switch (ConfirmationChannel.parse(channel)) {
      ConfirmationChannel.smsOtp => l10n.visitConfirmOtp,
      ConfirmationChannel.appPush => l10n.visitConfirmPush,
      ConfirmationChannel.qr => l10n.visitConfirmQr,
      null => channel,
    };

/// Localised purpose label of a wire value.
VisitPurpose purposeOf(String wire) => VisitPurpose.values.firstWhere(
  (p) => p.name == wire,
  orElse: () => VisitPurpose.advisory,
);

/// The four ProofChecklist rows for [detail] with the expected [proof]
/// (or the server components once stored: server wins).
List<ProofItem> proofItems(
  CoreLocalizations l10n,
  VisitDetail detail,
  VisitProof proof,
) {
  final server = detail.serverComponents;
  bool ok(String key, bool local) =>
      server == null || !detail.serverScored ? local : (server[key] ?? 0) > 0;
  final geofenceOk = ok('geofence', proof.geofenceOk);
  final overridePending =
      detail.geofenceResult == GeofenceResults.override &&
      detail.visit.overrideApprovedBy == null;
  final minMinutes = proof.minDuration.inMinutes;
  final durationOk = ok('duration', proof.durationOk);
  return <ProofItem>[
    ProofItem(
      kind: ProofKind.geofence,
      satisfied: geofenceOk,
      explanation: geofenceOk
          ? null
          : overridePending
          ? l10n.proofGeofenceOverride
          : l10n.proofGeofenceOutside,
    ),
    ProofItem(
      kind: ProofKind.photo,
      satisfied: ok('photo', proof.photoOk),
      explanation: ok('photo', proof.photoOk) ? l10n.proofPhotoDone : null,
    ),
    ProofItem(
      kind: ProofKind.farmerConfirmed,
      satisfied: ok('confirmation', proof.confirmed),
    ),
    ProofItem(
      kind: ProofKind.duration,
      satisfied: durationOk,
      explanation: durationOk
          ? l10n.proofDurationDone
          : l10n.visitDurationNeeds(proof.elapsed.inMinutes, minMinutes),
    ),
  ];
}

/// Score to show: the server's once stored (VV-004, server wins), else the
/// local expectation.
int shownScore(VisitDetail detail, VisitProof proof) =>
    detail.visit.score ?? proof.score;

/// Tinted status line used across the visit screens.
class VisitNotice extends StatelessWidget {
  /// Creates the notice.
  const VisitNotice({
    required this.text,
    required this.tone,
    this.icon,
    this.action,
    super.key,
  });

  /// Message.
  final String text;

  /// success | warning | danger | info.
  final String tone;

  /// Leading icon (defaults per tone).
  final IconData? icon;

  /// Optional action below the text.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.app.palette;
    final (Color color, Color container, IconData defaultIcon) = switch (tone) {
      'success' => (
        p.statusSuccess,
        p.statusSuccessContainer,
        Icons.check_circle_outline,
      ),
      'warning' => (
        p.statusWarning,
        p.statusWarningContainer,
        Icons.warning_amber_outlined,
      ),
      'danger' => (
        p.statusDanger,
        p.statusDangerContainer,
        Icons.error_outline,
      ),
      _ => (p.statusInfo, p.statusInfoContainer, Icons.info_outline),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: context.app.tint(container),
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.all(color: color, width: context.app.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon ?? defaultIcon, color: color),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    text,
                    style: context.app.text.body.copyWith(color: color),
                  ),
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
    );
  }
}

/// A padded scroll column: the visit screens are short, so every child is
/// built (tests and screen readers see the whole screen).
class VisitScroll extends StatelessWidget {
  /// Creates the column.
  const VisitScroll({
    required this.children,
    this.padding = const EdgeInsets.all(Tokens.spaceScreenPadding),
    super.key,
  });

  /// Content.
  final List<Widget> children;

  /// Outer padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}
