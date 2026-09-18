import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';

/// A05 Location and data disclosure (FA-011): four plain-language points,
/// "I agree", the full policy in a sheet and a read-aloud button (no TTS
/// yet). Shown in onboarding and again from A10 "Review policy" when the
/// server publishes a newer version.
class DisclosureScreen extends ConsumerWidget {
  /// Creates the screen; [onboarding] continues to A06 after agreeing,
  /// otherwise the screen pops.
  const DisclosureScreen({this.onboarding = true, super.key});

  /// Part of first-run onboarding.
  final bool onboarding;

  Future<void> _showPolicy(BuildContext context, LocationPolicyState s) {
    final l10n = CoreLocalizations.of(context);
    final app = context.app;
    final lang = Localizations.localeOf(context).languageCode;
    // The server's text in the app language when it sent one, else the
    // bundled translation of the same version.
    final text = s.current.text.containsKey(lang) || s.current.text.length > 1
        ? s.current.textFor(lang)
        : l10n.locationPolicyText;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, controller) => ListView(
          key: const Key('policy-sheet'),
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            Tokens.spaceScreenPadding,
            0,
            Tokens.spaceScreenPadding,
            Tokens.space8,
          ),
          children: <Widget>[
            Text(l10n.policySheetTitle, style: app.text.heading),
            const SizedBox(height: Tokens.space1),
            Text(
              l10n.disclosureVersion(s.current.version),
              style: app.text.caption.copyWith(
                color: app.palette.textSecondary,
              ),
            ),
            const SizedBox(height: Tokens.space4),
            Text(text, style: app.text.body),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final s = ref.watch(locationPolicyProvider);
    final points = <(IconData, String)>[
      (Icons.location_on_outlined, l10n.consentPoint1),
      (Icons.schedule_outlined, l10n.consentPoint2),
      (Icons.currency_rupee_outlined, l10n.consentPoint3),
      (Icons.visibility_outlined, l10n.consentPoint4),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.consentTitle),
        automaticallyImplyLeading: !onboarding,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.disclosureIntro,
                style: app.text.body.copyWith(color: p.textSecondary),
              ),
              if (s.needsReacceptance) ...<Widget>[
                const SizedBox(height: Tokens.space3),
                Container(
                  key: const Key('disclosure-updated'),
                  padding: const EdgeInsets.all(Tokens.space3),
                  decoration: BoxDecoration(
                    color: app.tint(p.statusWarningContainer),
                    borderRadius: BorderRadius.circular(Tokens.radiusCard),
                    border: Border.all(
                      color: p.statusWarning,
                      width: app.borderWidth,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.new_releases_outlined, color: p.statusWarning),
                      const SizedBox(width: Tokens.space2),
                      Expanded(
                        child: Text(
                          l10n.disclosureUpdated,
                          style: app.text.body,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Tokens.space4),
              for (final (icon, text) in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.space3),
                  child: Material(
                    color: p.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Tokens.radiusCard),
                      side: app.borderSide,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(Tokens.space3),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: Tokens.sizeTouchTargetMin,
                            height: Tokens.sizeTouchTargetMin,
                            decoration: BoxDecoration(
                              color: app.tint(p.primaryContainer),
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(app.borderSide),
                            ),
                            child: Icon(icon, color: p.primary),
                          ),
                          const SizedBox(width: Tokens.space3),
                          Expanded(child: Text(text, style: app.text.body)),
                        ],
                      ),
                    ),
                  ),
                ),
              Text(
                l10n.disclosureVersion(s.current.version),
                style: app.text.caption.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: Tokens.space3),
              Wrap(
                spacing: Tokens.space2,
                runSpacing: Tokens.space2,
                children: <Widget>[
                  AppButton(
                    key: const Key('disclosure-read-aloud'),
                    label: l10n.consentReadAloud,
                    icon: Icons.volume_up_outlined,
                    variant: AppButtonVariant.tertiary,
                    size: AppButtonSize.medium,
                    expand: false,
                    onPressed: () => ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(l10n.comingSoon))),
                  ),
                  AppButton(
                    key: const Key('disclosure-policy-link'),
                    label: l10n.consentPolicyLink,
                    icon: Icons.description_outlined,
                    variant: AppButtonVariant.tertiary,
                    size: AppButtonSize.medium,
                    expand: false,
                    onPressed: () => _showPolicy(context, s),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: AppButton(
            key: const Key('disclosure-agree'),
            label: l10n.consentAgree,
            icon: Icons.check,
            onPressed: !s.loaded
                ? null
                : () async {
                    await ref.read(locationPolicyProvider.notifier).accept();
                    if (!context.mounted) return;
                    if (onboarding) {
                      context.go(AppRoutes.permissions);
                    } else if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRoutes.home);
                    }
                  },
          ),
        ),
      ),
    );
  }
}
