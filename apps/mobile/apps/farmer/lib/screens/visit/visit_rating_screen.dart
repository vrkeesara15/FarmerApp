import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';

/// Quick reasons on F61 (wire values stored as the rating reason).
abstract final class VisitReasons {
  /// Reasons offered for a good visit (4–5).
  static const List<String> good = <String>[
    'useful_advice',
    'looked_at_crop',
    'on_time',
  ];

  /// Reasons offered for a poor visit (1–3).
  static const List<String> poor = <String>[
    'too_short',
    'did_not_see_crop',
    'advice_unclear',
  ];

  /// Localised chip label.
  static String label(CoreLocalizations l10n, String reason) =>
      switch (reason) {
        'useful_advice' => l10n.kisanReasonUsefulAdvice,
        'looked_at_crop' => l10n.kisanReasonLookedAtCrop,
        'on_time' => l10n.kisanReasonOnTime,
        'too_short' => l10n.kisanReasonTooShort,
        'did_not_see_crop' => l10n.kisanReasonDidNotSeeCrop,
        _ => l10n.kisanReasonAdviceUnclear,
      };
}

/// F61 rating (FM-011): five faces and quick reason chips (no typing),
/// sent with the confirmation token to `/v1/visits/{id}/farmer-confirm`
/// (stored against the visit); queued in the outbox when offline. Two
/// decisions: the face and one reason.
class VisitRatingScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const VisitRatingScreen({required this.visitId, this.token, super.key});

  /// Visit.
  final String visitId;

  /// Token from the push prompt or the scanned QR.
  final ConfirmToken? token;

  @override
  ConsumerState<VisitRatingScreen> createState() => _VisitRatingScreenState();
}

class _VisitRatingScreenState extends ConsumerState<VisitRatingScreen> {
  int? _rating;
  String? _reason;
  bool _busy = false;
  KisanWrite? _result;

  Future<void> _send({required bool withRating}) async {
    final token = widget.token;
    if (token == null) return;
    setState(() => _busy = true);
    final result = await ref
        .read(kisanRepositoryProvider)
        .confirmVisit(
          visitId: widget.visitId,
          token: token.raw,
          channel: token.channel ?? 'app_push',
          rating: withRating ? _rating : null,
          reason: withRating ? _reason : null,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
    if (result == KisanWrite.refused) {
      showKisanMessage(
        context,
        CoreLocalizations.of(context).kisanVisitTokenInvalid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final result = _result;
    if (widget.token == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.kisanRateTitle)),
        body: EmptyState(
          icon: Icons.qr_code_scanner,
          title: l10n.kisanScanTitle,
          help: l10n.kisanScanHelp,
          actionLabel: l10n.kisanScanButton,
          onAction: () => context.pushReplacement(AppRoutes.visitScan),
        ),
      );
    }
    if (result == KisanWrite.done || result == KisanWrite.queued) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.kisanRateTitle)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
            child: Column(
              key: const Key('visit-confirmed'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: Tokens.space8),
                Icon(Icons.check_circle, size: 96, color: p.statusSuccess),
                const SizedBox(height: Tokens.space3),
                Text(
                  result == KisanWrite.done
                      ? l10n.kisanVisitThanks
                      : l10n.kisanSavedWillSend,
                  textAlign: TextAlign.center,
                  style: app.text.title,
                ),
                const Spacer(),
                AppButton(
                  key: const Key('visit-done'),
                  label: l10n.actionDone,
                  icon: Icons.home_outlined,
                  onPressed: () => context.go(AppRoutes.home),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final reasons = _rating == null
        ? const <String>[]
        : _rating! >= 4
        ? VisitReasons.good
        : VisitReasons.poor;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanRateTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  Center(
                    child: AudioButton(
                      promptId: 'f61_rate',
                      text: l10n.kisanRateQuestion,
                    ),
                  ),
                  Rating(
                    key: const Key('visit-rating'),
                    title: l10n.kisanRateQuestion,
                    value: _rating,
                    onChanged: (v) => setState(() {
                      _rating = v;
                      _reason = null;
                    }),
                  ),
                  const SizedBox(height: Tokens.space4),
                  if (reasons.isNotEmpty) ...<Widget>[
                    Text(l10n.kisanRateWhy, style: app.text.heading),
                    const SizedBox(height: Tokens.space2),
                    Wrap(
                      spacing: Tokens.space2,
                      runSpacing: Tokens.space2,
                      children: <Widget>[
                        for (final r in reasons)
                          ChoiceChip(
                            key: Key('reason-$r'),
                            label: Text(VisitReasons.label(l10n, r)),
                            selected: _reason == r,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: (on) =>
                                setState(() => _reason = on ? r : null),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppButton(
                    key: const Key('rating-send'),
                    label: l10n.kisanSend,
                    icon: Icons.send,
                    loading: _busy,
                    onPressed: _rating == null || _busy
                        ? null
                        : () => _send(withRating: true),
                  ),
                  AppButton(
                    key: const Key('rating-skip'),
                    label: l10n.kisanConfirmWithoutRating,
                    variant: AppButtonVariant.tertiary,
                    onPressed: _busy ? null : () => _send(withRating: false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
