import 'dart:async';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../farmers/wizard_copy.dart';
import 'visit_copy.dart';

/// A31 Visit in progress (FA-015): timer, in-app camera only (no gallery
/// affordance anywhere), notes with a voice-input placeholder, crop stage,
/// live ProofChecklist from the local `VisitProofEvaluator` twin of the
/// server rule, farmer confirmation (A32) and Check out (A33).
class VisitScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const VisitScreen({required this.visitId, super.key});

  /// Visit id.
  final String visitId;

  @override
  ConsumerState<VisitScreen> createState() => _VisitScreenState();
}

class _VisitScreenState extends ConsumerState<VisitScreen> {
  final TextEditingController _notes = TextEditingController();
  bool _notesLoaded = false;
  PendingVisitPhoto? _pending;
  bool _cameraBusy = false;
  bool _busy = false;

  VisitFlow get _flow => ref.read(visitFlowProvider);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    setState(() => _cameraBusy = true);
    try {
      final pending = await _flow.capturePhoto();
      if (mounted) setState(() => _pending = pending);
    } on PhotoDecodeException {
      if (mounted) setState(() => _pending = null);
    } finally {
      if (mounted) setState(() => _cameraBusy = false);
    }
  }

  Future<void> _usePhoto() async {
    final pending = _pending;
    if (pending == null) return;
    setState(() => _pending = null);
    await _flow.acceptPhoto(widget.visitId, pending);
  }

  Future<void> _setStage(String stage) =>
      _flow.saveCapture(widget.visitId, cropStage: stage);

  Future<void> _openConfirm() async {
    await _flow.saveCapture(widget.visitId, notes: _notes.text);
    if (mounted) unawaited(context.push(VisitRoutes.confirm(widget.visitId)));
  }

  Future<void> _checkOut() async {
    setState(() => _busy = true);
    final done = await _flow.checkOut(widget.visitId, notes: _notes.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) context.pushReplacement(VisitRoutes.summary(widget.visitId));
  }

  Future<void> _retry() async {
    final l10n = CoreLocalizations.of(context);
    final out = await _flow.retryFromFarm(widget.visitId);
    if (!mounted) return;
    final text = switch (out.result) {
      RetryResult.retried => l10n.visitRetryQueued,
      RetryResult.stillOutside => l10n.visitRetryStillOutside(
        out.check?.distanceM?.round() ?? 0,
      ),
      RetryResult.noFix => l10n.visitNoFix,
      RetryResult.nothingToRetry => null,
    };
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    ref.watch(visitTickProvider);
    final detail = ref.watch(visitDetailProvider(widget.visitId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.visitInProgress),
        actions: <Widget>[
          SyncStatusPillLive(onTap: () => context.push(AppRoutes.syncDetails)),
          const SizedBox(width: Tokens.space3),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: detail.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorState(
                  onRetry: () =>
                      ref.invalidate(visitDetailProvider(widget.visitId)),
                ),
                data: (d) => d == null
                    ? EmptyState(title: l10n.visitsEmptyTitle)
                    : _body(context, l10n, d),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CoreLocalizations l10n, VisitDetail d) {
    final app = context.app;
    final p = app.palette;
    if (!_notesLoaded) {
      _notes.text = d.visit.notes ?? '';
      _notesLoaded = true;
    }
    final now = ref.read(clockProvider)();
    final proof = d.proofAt(now);
    final pending = _pending;
    final failure = d.failure;
    return VisitScroll(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(d.farmer?.name ?? '', style: app.text.title)),
            Icon(purposeOf(d.visit.purpose).icon, color: p.primary),
            const SizedBox(width: Tokens.space1),
            Text(purposeOf(d.visit.purpose).label(l10n), style: app.text.label),
          ],
        ),
        const SizedBox(height: Tokens.space2),
        if (failure != null)
          VisitNotice(
            key: const Key('visit-rejected'),
            tone: 'danger',
            text:
                '${l10n.visitRejectedTitle}. '
                '${failure.outsideGeofence && failure.distanceM != null
                    ? l10n.visitRejectedOutside(failure.distanceM!.round())
                    : failure.outsideGeofence
                    ? l10n.visitRejectedNoTarget
                    : failure.detail}',
            action: failure.outsideGeofence
                ? AppButton(
                    key: const Key('visit-retry'),
                    label: l10n.visitRetryFromFarm,
                    icon: Icons.my_location,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.medium,
                    expand: false,
                    onPressed: _retry,
                  )
                : null,
          )
        else
          Row(
            key: const Key('visit-sync-state'),
            children: <Widget>[
              Icon(
                d.pendingSync
                    ? Icons.cloud_upload_outlined
                    : Icons.cloud_done_outlined,
                color: d.pendingSync ? p.statusInfo : p.statusSuccess,
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Text(
                  d.pendingSync
                      ? l10n.visitCheckInPending
                      : l10n.visitCheckInSynced,
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
        const SizedBox(height: Tokens.space3),
        // Timer.
        Container(
          padding: const EdgeInsets.all(Tokens.space3),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Tokens.radiusCard),
            border: Border.fromBorderSide(app.borderSide),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.timer_outlined, color: p.primary),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.visitTimerLabel,
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                    Text(
                      formatCountdown(proof.elapsed),
                      key: const Key('visit-timer'),
                      style: app.text.display,
                    ),
                    Text(
                      l10n.visitMinDuration(proof.minDuration.inMinutes),
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: Tokens.space2),
                    Wrap(
                      spacing: Tokens.space2,
                      runSpacing: Tokens.space1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          d.serverScored
                              ? l10n.visitServerScore
                              : l10n.visitExpectedScore,
                          style: app.text.label,
                        ),
                        VisitScoreBadge(
                          key: const Key('visit-expected-score'),
                          score: shownScore(d, proof),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionTitle(l10n.visitProofTitle),
        ProofChecklist(
          key: const Key('visit-proof'),
          items: proofItems(l10n, d, proof),
        ),
        if (!proof.integrityOk)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Text(
              l10n.proofIntegrityIssue,
              key: const Key('visit-integrity-issue'),
              style: app.text.caption.copyWith(color: p.statusWarning),
            ),
          ),
        SectionTitle(
          l10n.visitPhotos,
          trailing: Text(
            l10n.visitPhotoCount(d.photos.length),
            style: app.text.caption.copyWith(color: p.textSecondary),
          ),
        ),
        Text(
          l10n.visitPhotosHelp,
          style: app.text.caption.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: Tokens.space2),
        if (d.photos.isNotEmpty)
          Wrap(
            spacing: Tokens.space2,
            runSpacing: Tokens.space2,
            children: <Widget>[
              for (final (i, photo) in d.photos.indexed)
                _PhotoTile(key: Key('visit-photo-$i'), photo: photo),
            ],
          ),
        const SizedBox(height: Tokens.space2),
        if (pending != null)
          PhotoReviewCard(
            key: const Key('visit-photo-review'),
            sizeBytes: pending.processed.sizeBytes,
            width: pending.processed.width,
            height: pending.processed.height,
            quality: pending.quality,
            thumbnail: MemoryImage(pending.processed.bytes),
            onRetake: _takePhoto,
            onUse: _usePhoto,
          )
        else
          AppButton(
            key: const Key('visit-take-photo'),
            label: l10n.visitTakePhoto,
            icon: Icons.photo_camera_outlined,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.medium,
            loading: _cameraBusy,
            onPressed: _cameraBusy || !d.open ? null : _takePhoto,
          ),
        SectionTitle(l10n.visitNotesLabel),
        VoiceTextField(
          label: l10n.visitNotesLabel,
          hintText: l10n.visitNotesHint,
          controller: _notes,
          enabled: d.open,
          maxLines: 3,
          fieldKey: const Key('visit-notes'),
          micKey: const Key('visit-voice'),
        ),
        const SizedBox(height: Tokens.space3),
        ChoiceChips(
          label: l10n.visitCropStageLabel,
          values: CropStages.values,
          labelOf: (v) => CropStages.label(l10n, v),
          iconOf: (_) => Icons.spa_outlined,
          selected: d.visit.cropStage,
          keyPrefix: 'visit-stage-',
          onSelected: d.open ? _setStage : (_) {},
        ),
        const SizedBox(height: Tokens.space4),
        AppButton(
          key: const Key('visit-confirm'),
          label: l10n.visitConfirmFarmer,
          icon: d.confirmed ? Icons.how_to_reg : Icons.how_to_reg_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: d.confirmed ? null : _openConfirm,
        ),
        const SizedBox(height: Tokens.space2),
        AppButton(
          key: const Key('visit-check-out'),
          label: l10n.visitCheckOut,
          icon: Icons.logout,
          loading: _busy,
          onPressed: _busy || !d.open || failure != null ? null : _checkOut,
        ),
        const SizedBox(height: Tokens.space6),
      ],
    );
  }
}

class _PhotoTile extends ConsumerStatefulWidget {
  const _PhotoTile({required this.photo, super.key});

  final VisitPhoto photo;

  @override
  ConsumerState<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends ConsumerState<_PhotoTile> {
  late final Future<Uint8List?>? _bytes = widget.photo.localPath == null
      ? null
      : ref.read(photoStoreProvider).read(widget.photo.localPath!);

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final placeholder = Icon(Icons.photo_outlined, color: p.primary);
    return Container(
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: app.tint(p.primaryContainer),
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: _bytes == null
          ? placeholder
          : FutureBuilder<Uint8List?>(
              future: _bytes,
              builder: (context, snap) => snap.data == null
                  ? placeholder
                  : Image.memory(snap.data!, fit: BoxFit.cover),
            ),
    );
  }
}
