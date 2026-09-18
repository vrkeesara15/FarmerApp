import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'steps/basics_step.dart';
import 'steps/boundary_step.dart';
import 'steps/consent_step.dart';
import 'steps/crops_step.dart';
import 'steps/review_step.dart';
import 'wizard_copy.dart';

/// A21 Add farmer wizard: `AppStepper` over five steps, state in
/// [registrationProvider], draft persisted in `kv` so an interrupted
/// registration resumes; Save queues everything for sync and opens A22.
class AddFarmerWizardScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AddFarmerWizardScreen({super.key});

  @override
  ConsumerState<AddFarmerWizardScreen> createState() =>
      _AddFarmerWizardScreenState();
}

class _AddFarmerWizardScreenState extends ConsumerState<AddFarmerWizardScreen> {
  bool _showIssues = false;
  bool _resumedShown = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final language = ref.read(settingsProvider).locale?.languageCode;
    final wizard = ref.read(registrationProvider.notifier);
    final before = await ref
        .read(appDatabaseProvider)
        .getValue(RegistrationDraft.kvKey);
    await wizard.start(language: language);
    if (!mounted) return;
    final draft = ref.read(registrationProvider).draft;
    if (before != null &&
        draft != null &&
        !_resumedShown &&
        (draft.step > 0 || draft.name.isNotEmpty || draft.phone.isNotEmpty)) {
      _resumedShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CoreLocalizations.of(context).regResumeDraft)),
      );
    }
  }

  Future<void> _next() async {
    final wizard = ref.read(registrationProvider.notifier);
    final issues = await wizard.next();
    if (!mounted) return;
    setState(() => _showIssues = issues.isNotEmpty);
    if (issues.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CoreLocalizations.of(context).regFixIssues)),
      );
    }
  }

  Future<void> _save() async {
    final wizard = ref.read(registrationProvider.notifier);
    final issues = await wizard.save();
    if (!mounted) return;
    if (issues.isNotEmpty) {
      setState(() => _showIssues = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CoreLocalizations.of(context).regFixIssues)),
      );
      return;
    }
    final id = ref.read(registrationProvider).savedFarmerId!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(CoreLocalizations.of(context).regSaved)),
    );
    context.go(AppRoutes.farmerPath(id));
  }

  Future<void> _discard() async {
    await ref.read(registrationProvider.notifier).discard();
    if (mounted) context.go(AppRoutes.farmers);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(registrationProvider);
    final wizard = ref.read(registrationProvider.notifier);
    final draft = state.draft;
    if (draft == null || draft.mode != DraftMode.newFarmer) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.regTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final steps = wizard.steps;
    final step = wizard.currentStep;
    final index = steps.indexOf(step);
    final last = index == steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.regTitle),
        leading: BackButton(
          onPressed: () {
            if (index == 0) {
              context.go(AppRoutes.farmers);
            } else {
              unawaited(wizard.back());
            }
          },
        ),
        actions: <Widget>[
          TextButton.icon(
            key: const Key('reg-discard'),
            onPressed: _discard,
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.regDiscardDraft),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          decoration: BoxDecoration(
            color: app.palette.surface,
            border: Border(top: app.borderSide),
          ),
          child: Row(
            children: <Widget>[
              if (index > 0) ...<Widget>[
                AppButton(
                  key: const Key('reg-back'),
                  label: l10n.actionBack,
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  icon: Icons.arrow_back,
                  onPressed: () => unawaited(wizard.back()),
                ),
                const SizedBox(width: Tokens.space3),
              ],
              Expanded(
                child: last
                    ? AppButton(
                        key: const Key('reg-save'),
                        label: l10n.regSave,
                        icon: Icons.save_outlined,
                        loading: state.saving,
                        onPressed: _save,
                      )
                    : AppButton(
                        key: const Key('reg-next'),
                        label: l10n.actionNext,
                        icon: Icons.arrow_forward,
                        onPressed: _next,
                      ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.spaceScreenPadding,
                Tokens.space3,
                Tokens.spaceScreenPadding,
                0,
              ),
              child: AppStepper(
                steps: <String>[for (final s in steps) stepTitle(l10n, s)],
                currentIndex: index,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey<String>('reg-step-${step.name}'),
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                child: switch (step) {
                  RegistrationStep.basics => BasicsStep(
                    showIssues: _showIssues,
                  ),
                  RegistrationStep.boundary => BoundaryStep(
                    showIssues: _showIssues,
                  ),
                  RegistrationStep.crops => CropsStep(showIssues: _showIssues),
                  RegistrationStep.consent => ConsentStep(
                    showIssues: _showIssues,
                  ),
                  RegistrationStep.review => ReviewStep(
                    showIssues: _showIssues,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
