import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'visit_copy.dart';

enum _Mode { choose, otp, push, qr }

/// A32 Farmer confirmation (FA-016): OTP by SMS (online only), "Ask in
/// Kisan app" (queued offline, waiting until the pull brings
/// `confirmed_at`) or "Show QR" (token from the request; needs one sync
/// first). Waiting and confirmed states.
class ConfirmScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ConfirmScreen({required this.visitId, super.key});

  /// Visit id.
  final String visitId;

  @override
  ConsumerState<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends ConsumerState<ConfirmScreen> {
  _Mode? _mode;
  String? _message;
  String? _otpError;
  String? _phone;
  bool _busy = false;

  VisitFlow get _flow => ref.read(visitFlowProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_flow.flushQueuedConfirmations());
  }

  _Mode _resume(VisitDetail d) {
    final last = d.latestConfirmation;
    if (last == null) return _Mode.choose;
    final waiting =
        last.status == ConfirmationStatuses.pending ||
        last.status == ConfirmationStatuses.queued;
    if (!waiting) return _Mode.choose;
    return switch (ConfirmationChannel.parse(last.channel)) {
      ConfirmationChannel.appPush => _Mode.push,
      ConfirmationChannel.qr when last.token != null => _Mode.qr,
      _ => _Mode.choose,
    };
  }

  Future<void> _ask(ConfirmationChannel channel) async {
    final l10n = CoreLocalizations.of(context);
    setState(() {
      _busy = true;
      _message = null;
      _otpError = null;
    });
    final out = await _flow.requestConfirmation(widget.visitId, channel);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (out.result) {
        case RequestResult.ok:
          _phone = out.api?.phoneMasked;
          _mode = switch (channel) {
            ConfirmationChannel.smsOtp => _Mode.otp,
            ConfirmationChannel.appPush => _Mode.push,
            ConfirmationChannel.qr => _Mode.qr,
          };
        case RequestResult.queuedOffline:
          _mode = _Mode.push;
          _message = l10n.visitConfirmQueued;
        case RequestResult.needsNetwork:
          _message = channel == ConfirmationChannel.qr
              ? l10n.visitConfirmQrNeedsSync
              : l10n.visitConfirmNeedsNetwork;
        case RequestResult.notSynced:
          _message = l10n.visitConfirmNotSynced;
        case RequestResult.alreadyConfirmed:
          _message = l10n.visitConfirmAlready;
        case RequestResult.refused:
          _message = l10n.visitConfirmRefused;
      }
    });
  }

  Future<void> _submitOtp(String code) async {
    final l10n = CoreLocalizations.of(context);
    setState(() => _busy = true);
    final out = await _flow.confirmOtp(widget.visitId, code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _otpError = switch (out.result) {
        OtpConfirmResult.ok || OtpConfirmResult.alreadyConfirmed => null,
        OtpConfirmResult.invalid =>
          out.attemptsLeft == null
              ? l10n.otpInvalid
              : '${l10n.otpInvalid} ${l10n.otpAttemptsLeft(out.attemptsLeft!)}',
        OtpConfirmResult.expired ||
        OtpConfirmResult.notFound => l10n.otpExpired,
        OtpConfirmResult.locked => l10n.otpLocked(
          ((out.retryAfter?.inSeconds ?? 900) + 59) ~/ 60,
        ),
        OtpConfirmResult.network => l10n.visitConfirmNeedsNetwork,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    final detail = ref.watch(visitDetailProvider(widget.visitId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.visitConfirmTitle)),
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
    if (d.confirmed) {
      final channel = d.visit.confirmationChannel != 'none'
          ? d.visit.confirmationChannel
          : d.confirmations
                    .where((c) => c.status == ConfirmationStatuses.confirmed)
                    .lastOrNull
                    ?.channel ??
                '';
      return VisitScroll(
        key: const Key('confirm-done'),
        children: <Widget>[
          const SizedBox(height: Tokens.space8),
          Icon(Icons.verified_user, size: 96, color: p.statusSuccess),
          const SizedBox(height: Tokens.space3),
          Text(
            l10n.visitConfirmed,
            textAlign: TextAlign.center,
            style: app.text.title,
          ),
          if (channel.isNotEmpty)
            Text(
              l10n.visitConfirmedVia(channelLabel(l10n, channel)),
              textAlign: TextAlign.center,
              style: app.text.body.copyWith(color: p.textSecondary),
            ),
          const SizedBox(height: Tokens.space6),
          AppButton(
            key: const Key('confirm-continue'),
            label: l10n.visitConfirmContinue,
            icon: Icons.arrow_forward,
            onPressed: () => context.pop(),
          ),
        ],
      );
    }
    final mode = _mode ?? _resume(d);
    final last = d.latestConfirmation;
    return VisitScroll(
      children: <Widget>[
        Text(d.farmer?.name ?? '', style: app.text.title),
        const SizedBox(height: Tokens.space2),
        if (_message != null) ...<Widget>[
          VisitNotice(
            key: const Key('confirm-message'),
            text: _message!,
            tone: mode == _Mode.push ? 'info' : 'warning',
          ),
          const SizedBox(height: Tokens.space3),
        ],
        switch (mode) {
          _Mode.choose => _choose(l10n),
          _Mode.otp => Column(
            key: const Key('confirm-otp-state'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_phone != null)
                Text(l10n.visitConfirmOtpSent(_phone!), style: app.text.body),
              const SizedBox(height: Tokens.space3),
              OtpInput(
                key: const Key('confirm-otp-input'),
                enabled: !_busy,
                errorText: _otpError,
                onCompleted: _submitOtp,
                onResend: () => _ask(ConfirmationChannel.smsOtp),
              ),
            ],
          ),
          _Mode.push => Column(
            key: const Key('confirm-push-waiting'),
            children: <Widget>[
              const SizedBox(height: Tokens.space4),
              const CircularProgressIndicator(),
              const SizedBox(height: Tokens.space3),
              Text(l10n.visitConfirmWaiting, style: app.text.heading),
              const SizedBox(height: Tokens.space1),
              Text(
                l10n.visitConfirmWaitingPush,
                textAlign: TextAlign.center,
                style: app.text.body.copyWith(color: p.textSecondary),
              ),
            ],
          ),
          _Mode.qr => Column(
            key: const Key('confirm-qr-state'),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(Tokens.space3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Tokens.radiusCard),
                  border: Border.fromBorderSide(app.borderSide),
                ),
                child: QrImageView(
                  key: const Key('confirm-qr-image'),
                  data: last?.token ?? '',
                  size: 220,
                  semanticsLabel: l10n.visitConfirmQrHelp,
                ),
              ),
              const SizedBox(height: Tokens.space3),
              Text(l10n.visitConfirmQrWaiting, style: app.text.heading),
              Text(
                l10n.visitConfirmQrHelp,
                textAlign: TextAlign.center,
                style: app.text.body.copyWith(color: p.textSecondary),
              ),
              if (last?.expiresAt != null)
                Text(
                  l10n.visitConfirmExpires(
                    last!.expiresAt!
                        .toUtc()
                        .difference(ref.read(clockProvider)())
                        .inMinutes
                        .clamp(0, 24 * 60),
                  ),
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
            ],
          ),
        },
        const SizedBox(height: Tokens.space4),
        if (mode != _Mode.choose)
          AppButton(
            key: const Key('confirm-another'),
            label: l10n.visitConfirmChooseAnother,
            icon: Icons.swap_horiz,
            variant: AppButtonVariant.tertiary,
            size: AppButtonSize.medium,
            onPressed: () => setState(() {
              _mode = _Mode.choose;
              _message = null;
            }),
          ),
        AppButton(
          key: const Key('confirm-later'),
          label: l10n.visitConfirmLater,
          icon: Icons.schedule,
          variant: AppButtonVariant.secondary,
          onPressed: () => context.pop(),
        ),
      ],
    );
  }

  Widget _choose(CoreLocalizations l10n) {
    final app = context.app;
    final p = app.palette;
    Widget option(
      String key,
      IconData icon,
      String title,
      String help,
      ConfirmationChannel channel,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: app.borderSide,
        ),
        child: ListTile(
          key: Key(key),
          enabled: !_busy,
          minVerticalPadding: Tokens.space3,
          leading: Icon(icon, color: p.primary, size: Tokens.space8),
          title: Text(title, style: app.text.heading),
          subtitle: Text(
            help,
            style: app.text.body.copyWith(color: p.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _ask(channel),
        ),
      ),
    );
    return Column(
      key: const Key('confirm-choose'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.visitConfirmIntro, style: app.text.body),
        const SizedBox(height: Tokens.space3),
        option(
          'confirm-otp',
          Icons.sms_outlined,
          l10n.visitConfirmOtp,
          l10n.visitConfirmOtpHelp,
          ConfirmationChannel.smsOtp,
        ),
        option(
          'confirm-push',
          Icons.phone_android,
          l10n.visitConfirmPush,
          l10n.visitConfirmPushHelp,
          ConfirmationChannel.appPush,
        ),
        option(
          'confirm-qr',
          Icons.qr_code_2,
          l10n.visitConfirmQr,
          l10n.visitConfirmQrHelp,
          ConfirmationChannel.qr,
        ),
      ],
    );
  }
}
