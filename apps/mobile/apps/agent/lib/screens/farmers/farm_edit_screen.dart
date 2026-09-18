import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'steps/boundary_step.dart';
import 'steps/crops_step.dart';
import 'wizard_copy.dart';

/// A23 Add second farm / edit farm: the A21b + A21c steps for one farm of
/// an existing farmer; Save queues `farm` + `crop_plot` ops (FA-013).
class FarmEditScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [farmerId]; [farmId] null adds a farm.
  const FarmEditScreen({required this.farmerId, this.farmId, super.key});

  /// Owning farmer.
  final String farmerId;

  /// Farm to edit, or null to add one.
  final String? farmId;

  @override
  ConsumerState<FarmEditScreen> createState() => _FarmEditScreenState();
}

class _FarmEditScreenState extends ConsumerState<FarmEditScreen> {
  bool _showIssues = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(registrationProvider.notifier)
          .start(
            mode: DraftMode.farm,
            farmerId: widget.farmerId,
            farmId: widget.farmId,
          ),
    );
  }

  Future<void> _next() async {
    final issues = await ref.read(registrationProvider.notifier).next();
    if (!mounted) return;
    setState(() => _showIssues = issues.isNotEmpty);
  }

  Future<void> _save() async {
    final issues = await ref.read(registrationProvider.notifier).save();
    if (!mounted) return;
    if (issues.isNotEmpty) {
      setState(() => _showIssues = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CoreLocalizations.of(context).regFixIssues)),
      );
      return;
    }
    context.go(AppRoutes.farmerPath(widget.farmerId));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(registrationProvider);
    final wizard = ref.read(registrationProvider.notifier);
    final draft = state.draft;
    final title = widget.farmId == null
        ? l10n.farmAddTitle
        : l10n.farmEditTitle;
    if (draft == null ||
        draft.mode != DraftMode.farm ||
        draft.farmerId != widget.farmerId) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final steps = wizard.steps;
    final step = wizard.currentStep;
    final index = steps.indexOf(step);
    final last = index == steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () {
            if (index == 0) {
              context.go(AppRoutes.farmerPath(widget.farmerId));
            } else {
              unawaited(wizard.back());
            }
          },
        ),
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
                  key: const Key('farm-back'),
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
                        key: const Key('farm-save'),
                        label: l10n.regSaveFarm,
                        icon: Icons.save_outlined,
                        loading: state.saving,
                        onPressed: _save,
                      )
                    : AppButton(
                        key: const Key('farm-next'),
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
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                child: step == RegistrationStep.boundary
                    ? BoundaryStep(showIssues: _showIssues)
                    : CropsStep(showIssues: _showIssues, allowAddFarm: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
