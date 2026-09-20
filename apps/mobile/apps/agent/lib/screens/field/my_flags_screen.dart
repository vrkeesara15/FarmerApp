import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'field_widgets.dart';

/// A62 My flags (VA-005): the flags raised about this officer and nobody
/// else's.
///
/// An open flag shows what the rule found and an "add explanation" field;
/// the outcome is hidden until the flag is resolved, exactly as the server
/// serves it (`GET /v1/flags/mine` never sends an outcome while open).
/// Explaining needs connectivity — the server refuses an explanation on a
/// resolved flag, so it is never queued blind.
class MyFlagsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MyFlagsScreen({super.key});

  @override
  ConsumerState<MyFlagsScreen> createState() => _MyFlagsScreenState();
}

class _MyFlagsScreenState extends ConsumerState<MyFlagsScreen> {
  final Set<String> _sending = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(fieldRepositoryProvider).refreshFlags());
  }

  Future<void> _explain(MyFlag flag, String body) async {
    if (body.trim().isEmpty) return;
    setState(() => _sending.add(flag.id));
    final l10n = CoreLocalizations.of(context);
    try {
      await ref.read(fieldRepositoryProvider).explainFlag(flag.id, body.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.flagExplanationSent)));
    } on FieldUnavailableException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('flag-explain-offline'),
          content: Text(l10n.flagExplanationNeedsNetwork),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending.remove(flag.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final cached = ref.watch(myFlagsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.flagsTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: cached.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    ErrorState(onRetry: () => ref.invalidate(myFlagsProvider)),
                data: (view) {
                  final flags = view.value ?? const <MyFlag>[];
                  if (flags.isEmpty) {
                    return EmptyState(
                      key: const Key('flags-empty'),
                      icon: Icons.flag_outlined,
                      title: l10n.flagsEmpty,
                      help: l10n.flagsEmptyHelp,
                    );
                  }
                  final open = <MyFlag>[
                    for (final f in flags)
                      if (!f.resolved) f,
                  ];
                  final resolved = <MyFlag>[
                    for (final f in flags)
                      if (f.resolved) f,
                  ];
                  return ListView(
                    padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                    children: <Widget>[
                      if (view.asOf != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FieldCaption(
                            l10n.fieldAsOf(formatDateTimeIst(view.asOf!)),
                            icon: Icons.schedule,
                          ),
                        ),
                      if (open.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Tokens.space2),
                        Text(l10n.flagsOpenSection, style: app.text.heading),
                        const SizedBox(height: Tokens.space2),
                        for (final f in open)
                          _FlagCard(
                            flag: f,
                            sending: _sending.contains(f.id),
                            onExplain: (body) => unawaited(_explain(f, body)),
                          ),
                      ],
                      if (resolved.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Tokens.space2),
                        Text(
                          l10n.flagsResolvedSection,
                          style: app.text.heading,
                        ),
                        const SizedBox(height: Tokens.space2),
                        for (final f in resolved)
                          _FlagCard(flag: f, sending: false),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagCard extends StatefulWidget {
  const _FlagCard({required this.flag, required this.sending, this.onExplain});

  final MyFlag flag;
  final bool sending;
  final ValueChanged<String>? onExplain;

  @override
  State<_FlagCard> createState() => _FlagCardState();
}

class _FlagCardState extends State<_FlagCard> {
  final TextEditingController _body = TextEditingController();

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final flag = widget.flag;
    final severityColor = switch (flag.severity) {
      'high' => p.statusDanger,
      'medium' => p.statusWarning,
      _ => p.statusInfo,
    };
    final severityLabel = switch (flag.severity) {
      'high' => l10n.flagSeverityHigh,
      'medium' => l10n.flagSeverityMedium,
      _ => l10n.flagSeverityLow,
    };
    final stateLabel = switch (flag.state) {
      'resolved' => l10n.flagStateResolved,
      'in_review' => l10n.flagStateInReview,
      _ => l10n.flagStateOpen,
    };
    return FieldCard(
      key: Key('flag-${flag.id}'),
      borderColor: flag.resolved ? null : severityColor,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.flag_outlined, color: severityColor),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    flag.ruleTitle ?? flag.title,
                    style: app.text.label,
                  ),
                ),
                FieldCaption(severityLabel, color: severityColor),
              ],
            ),
            const SizedBox(height: Tokens.space1),
            FieldCaption(
              '$stateLabel · ${formatDateIst(flag.createdAt)}',
              icon: Icons.schedule,
            ),
            if (flag.title.isNotEmpty && flag.ruleTitle != null) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              Text(flag.title, style: app.text.body),
            ],
            if (flag.explanations.isNotEmpty) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              for (final e in flag.explanations)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.space1),
                  child: Text(
                    '“${e.body}”',
                    key: Key('flag-explanation-${e.id}'),
                    style: app.text.body.copyWith(color: p.textSecondary),
                  ),
                ),
            ],
            if (flag.resolved && flag.outcome != null) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              Container(
                key: Key('flag-outcome-${flag.id}'),
                padding: const EdgeInsets.all(Tokens.space2),
                decoration: BoxDecoration(
                  color: app.tint(p.statusSuccessContainer),
                  borderRadius: BorderRadius.circular(Tokens.radiusChip),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.flagOutcomeTitle, style: app.text.label),
                    Text(
                      flag.outcome!.label ?? flag.outcome!.status,
                      style: app.text.body,
                    ),
                    if (flag.outcome!.note != null)
                      Text(flag.outcome!.note!, style: app.text.caption),
                  ],
                ),
              ),
            ] else if (!flag.resolved) ...<Widget>[
              const SizedBox(height: Tokens.space2),
              FieldCaption(
                l10n.flagOutcomeHidden,
                key: Key('flag-outcome-hidden-${flag.id}'),
                icon: Icons.lock_outline,
              ),
            ],
            if (flag.canExplain && widget.onExplain != null) ...<Widget>[
              const SizedBox(height: Tokens.space3),
              VoiceTextField(
                label: l10n.flagExplanationLabel,
                hintText: l10n.flagExplanationHint,
                controller: _body,
                maxLines: 3,
                fieldKey: Key('flag-explain-field-${flag.id}'),
                micKey: Key('flag-explain-mic-${flag.id}'),
              ),
              const SizedBox(height: Tokens.space2),
              AppButton(
                key: Key('flag-explain-send-${flag.id}'),
                label: l10n.flagAddExplanation,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                loading: widget.sending,
                onPressed: () => widget.onExplain!(_body.text),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
