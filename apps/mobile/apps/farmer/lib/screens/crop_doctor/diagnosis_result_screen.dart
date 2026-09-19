import 'dart:async';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';
import 'crop_doctor_common.dart';

/// F24–F28 for one crop check (FM-005, FM-006):
///
/// * F24 while waiting: "Checking your crop…" (polling), or offline "Saved
///   on your phone — we'll check when you're online";
/// * F25 high confidence: name in the farmer's language, confidence in
///   words, "check these signs", Organic / Chemical with dose per acre and
///   per 15 L tank (tank pictogram), PHI and PPE pictograms, ranked
///   products at "FCC Kondapur, 3 km", **Order** and **Call my officer**;
/// * F26 provisional: "Our expert will confirm within 24 hours", **no buy
///   button**, "Talk to your field officer" (SPEC 3.4);
/// * F27 updated by the agronomist: banner + earlier answers;
/// * F28 not a plant / unsupported crop: friendly message, "Ask an expert".
///
/// Everything is read from the phone's store, so a result stays readable
/// offline (NF-002).
class DiagnosisResultScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const DiagnosisResultScreen({required this.diagnosisId, super.key});

  /// Diagnosis id.
  final String diagnosisId;

  @override
  ConsumerState<DiagnosisResultScreen> createState() =>
      _DiagnosisResultScreenState();
}

class _DiagnosisResultScreenState extends ConsumerState<DiagnosisResultScreen> {
  DiagnosisPoller? _poller;
  bool? _banner;

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
  }

  Future<void> _poll() async {
    final poller = DiagnosisPoller(
      repository: ref.read(diagnosisRepositoryProvider),
      sleep: ref.read(diagnosisPollSleepProvider),
      flush: ref.read(kisanFlushProvider),
    );
    _poller = poller;
    await poller.run(widget.diagnosisId).catchError((Object _) => null);
  }

  @override
  void dispose() {
    _poller?.stop();
    super.dispose();
  }

  Future<void> _askExpert() async {
    final l10n = CoreLocalizations.of(context);
    final (outcome, _) = await ref
        .read(diagnosisRepositoryProvider)
        .askExpert(widget.diagnosisId);
    await ref.read(kisanFlushProvider)().catchError((Object _) {});
    if (!mounted) return;
    showKisanMessage(
      context,
      outcome == AskExpertOutcome.alreadyWithExpert
          ? l10n.cropDoctorAskExpertAlready
          : l10n.cropDoctorAskExpertSent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final async = ref.watch(diagnosisProvider(widget.diagnosisId));
    final d = async.value;
    if (d != null && _banner == null && !d.status.isWaiting) {
      // F27: the banner stays for this visit; the list stops flagging it.
      _banner = d.updateUnseen;
      if (d.updateUnseen) {
        unawaited(
          ref.read(diagnosisRepositoryProvider).markSeen(widget.diagnosisId),
        );
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cropDoctorResultTitle),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.cropDoctor),
        ),
      ),
      bottomNavigationBar: d == null || d.status.isWaiting
          ? null
          : DiagnosisActionBar(
              diagnosis: d,
              onOrder: d.showBuy && d.recommended != null
                  ? () => orderFromDiagnosis(context, ref, d, d.recommended!)
                  : null,
              onCallOfficer: () => callMyOfficer(context, ref),
              onAskExpert: _askExpert,
            ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: d == null
                  ? async.hasValue
                        // Not on this phone (the poll stores it if the
                        // server has it).
                        ? EmptyState(
                            icon: Icons.search_off,
                            title: l10n.cropDoctorNotOnPhone,
                          )
                        : const Center(child: CircularProgressIndicator())
                  : d.status.isWaiting
                  ? _Waiting(diagnosis: d)
                  : _Result(diagnosis: d, banner: _banner ?? false),
            ),
          ],
        ),
      ),
    );
  }
}

/// F24 Analysing, or queued offline.
class _Waiting extends ConsumerWidget {
  const _Waiting({required this.diagnosis});

  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final offline = ref.watch(offlineProvider);
    final queued = diagnosis.waitingForNetwork && offline;
    final failed = diagnosis.failureCode != null;
    final title = failed
        ? l10n.cropDoctorSendFailed
        : queued
        ? l10n.cropDoctorQueuedTitle
        : l10n.cropDoctorAnalysing;
    final help = queued
        ? l10n.cropDoctorQueuedHelp
        : l10n.cropDoctorAnalysingHelp;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
        child: Column(
          key: Key(queued ? 'diagnosis-queued' : 'diagnosis-analysing'),
          children: <Widget>[
            if (queued || failed)
              Icon(
                failed ? Icons.error_outline : Icons.cloud_off_outlined,
                size: 72,
                color: failed ? p.statusDanger : p.statusInfo,
              )
            else
              const SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(strokeWidth: 6),
              ),
            const SizedBox(height: Tokens.space4),
            Text(title, textAlign: TextAlign.center, style: app.text.title),
            const SizedBox(height: Tokens.space2),
            if (!failed)
              SpokenText(
                promptId: queued ? 'f24_queued' : 'f24_analysing',
                text: help,
              ),
          ],
        ),
      ),
    );
  }
}

class _Result extends ConsumerWidget {
  const _Result({required this.diagnosis, required this.banner});

  final Diagnosis diagnosis;
  final bool banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final d = diagnosis;
    final store = d.store;
    final km = store == null
        ? null
        : ref.watch(diagnosisStoreLabelProvider(store.id)).value;
    final storeLabel = store == null
        ? null
        : km == null
        ? store.name
        : l10n.cropDoctorStoreDistance(store.name, km);
    final photo = d.localPhotos.isEmpty
        ? null
        : ref.watch(_photoProvider(d.localPhotos.first)).value;
    return ListView(
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      children: <Widget>[
        DiagnosisResultView(
          diagnosis: d,
          photo: photo == null ? null : MemoryImage(photo),
          storeLabel: storeLabel,
          showUpdatedBanner: banner,
          onOrder: d.showBuy
              ? (option) => orderFromDiagnosis(context, ref, d, option)
              : null,
        ),
        if (d.hasResult)
          AudioButton(
            promptId: 'f25_result',
            text:
                '${diagnosisHeadline(l10n, d)}. '
                '${d.problem!.nameIn(Localizations.localeOf(context).languageCode)}',
          ),
      ],
    );
  }
}

final _photoProvider = FutureProvider.family<Uint8List?, String>(
  (ref, path) => ref.watch(photoStoreProvider).read(path),
);
