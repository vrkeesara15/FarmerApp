import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';
import 'crop_doctor_common.dart';

/// F20 Crop doctor (FM-004): three picture tips (read aloud), "up to 3
/// photos", a big Open camera button, and the farmer's earlier crop checks
/// (cached on the phone, NF-002) with the ones the expert updated first.
class CropDoctorScreen extends ConsumerWidget {
  /// Creates the screen.
  const CropDoctorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final checks = ref.watch(diagnosesProvider).value ?? const <Diagnosis>[];
    final crops = ref.watch(cropsProvider).value ?? const <CropRef>[];
    final tips = <(IconData, String)>[
      (Icons.crop_free, l10n.cropDoctorIntroTip1),
      (Icons.wb_sunny_outlined, l10n.cropDoctorIntroTip2),
      (Icons.back_hand_outlined, l10n.cropDoctorIntroTip3),
    ];
    return KisanTabScaffold(
      tab: KisanTab.cropDoctor,
      title: l10n.cropDoctorTitle,
      body: ListView(
        padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
        children: <Widget>[
          Text(l10n.cropDoctorIntroTitle, style: app.text.title),
          const SizedBox(height: Tokens.space3),
          Row(
            key: const Key('crop-doctor-tips'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final (i, (icon, text)) in tips.indexed) ...<Widget>[
                if (i > 0) const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(Tokens.space2),
                    decoration: BoxDecoration(
                      color: app.tint(p.primaryContainer),
                      borderRadius: BorderRadius.circular(Tokens.radiusCard),
                      border: Border.fromBorderSide(app.borderSide),
                    ),
                    child: Column(
                      children: <Widget>[
                        Icon(icon, size: Tokens.space12, color: p.primary),
                        const SizedBox(height: Tokens.space1),
                        Text(
                          text,
                          textAlign: TextAlign.center,
                          style: app.text.label,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          AudioButton(
            promptId: 'f20_intro',
            text:
                '${l10n.cropDoctorIntroTitle}. ${tips.map((t) => t.$2).join('. ')}. '
                '${l10n.cropDoctorUpTo3}.',
          ),
          Text(
            l10n.cropDoctorUpTo3,
            style: app.text.body.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: Tokens.space3),
          SizedBox(
            height: 96,
            child: FilledButton.icon(
              key: const Key('crop-doctor-start'),
              style: FilledButton.styleFrom(
                backgroundColor: p.primary,
                foregroundColor: p.primaryOn,
                textStyle: app.text.title,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusCard),
                ),
              ),
              onPressed: () {
                ref.read(cropDoctorCaptureProvider.notifier).start();
                context.push(AppRoutes.cropCamera);
              },
              icon: const Icon(Icons.camera_alt, size: 40),
              label: Text(l10n.cropDoctorOpenCamera),
            ),
          ),
          if (checks.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.space6),
            Text(l10n.cropDoctorMyChecks, style: app.text.heading),
            const SizedBox(height: Tokens.space2),
            for (final d in <Diagnosis>[
              ...checks.where((d) => d.updateUnseen),
              ...checks.where((d) => !d.updateUnseen),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.space2),
                child: _CheckTile(
                  diagnosis: d,
                  title:
                      d.problem?.nameIn(lang) ??
                      (d.isOutOfScope
                          ? diagnosisOutOfScopeTitle(l10n, d.outOfScopeReason)
                          : d.cropCode == null
                          ? l10n.cropDoctorWaiting
                          : cropCodeName(context, crops, d.cropCode!)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.diagnosis, required this.title});

  final Diagnosis diagnosis;
  final String title;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final d = diagnosis;
    final when = d.capturedAt == null ? '' : formatDateTimeIst(d.capturedAt!);
    return KisanCard(
      key: Key('crop-check-${d.id}'),
      onTap: () => context.push(AppRoutes.cropResult(d.id)),
      child: Row(
        children: <Widget>[
          Icon(
            d.updateUnseen
                ? Icons.notifications_active_outlined
                : d.status.isWaiting
                ? Icons.hourglass_top_outlined
                : Icons.eco_outlined,
            color: d.updateUnseen ? p.statusInfo : p.primary,
          ),
          const SizedBox(width: Tokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: app.text.heading),
                if (d.updateUnseen)
                  Text(
                    l10n.cropDoctorUpdatedTitle,
                    style: app.text.caption.copyWith(color: p.statusInfo),
                  )
                else if (d.status.isWaiting)
                  Text(
                    d.waitingForNetwork
                        ? l10n.cropDoctorQueuedHelp
                        : l10n.cropDoctorWaiting,
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  )
                else if (d.confidence != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Tokens.space1),
                    child: ConfidenceBand(level: d.confidence!),
                  ),
                if (when.isNotEmpty)
                  Text(
                    when,
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
