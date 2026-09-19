import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../start.dart';

/// F03 OTP entry with resend timer; a correct code continues straight to
/// consent / welcome / home (no extra tap, FM-001 < 60 s).
class OtpScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  bool _leaving = false;

  Future<void> _continue() async {
    if (_leaving) return;
    _leaving = true;
    final next = await routeAfterLogin(ref);
    if (mounted) context.go(next);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final flow = ref.watch(authFlowProvider);
    final notifier = ref.read(authFlowProvider.notifier);
    ref.listen<AuthFlowState>(authFlowProvider, (previous, next) {
      if (next.step == AuthStep.done && previous?.step != AuthStep.done) {
        _continue();
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.otpTitle),
        leading: BackButton(
          onPressed: () {
            notifier.reset();
            context.go(AppRoutes.phone);
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.otpSubtitle(flow.phone),
                style: app.text.body.copyWith(color: app.palette.textSecondary),
              ),
              const SizedBox(height: Tokens.space6),
              OtpInput(
                enabled: !flow.busy && !flow.locked,
                errorText: flow.otpError ? authFailureText(l10n, flow) : null,
                onCompleted: notifier.verifyOtp,
                onResend: notifier.resendOtp,
              ),
              if (flow.step == AuthStep.done) ...<Widget>[
                const SizedBox(height: Tokens.space6),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_outline,
                      color: app.palette.statusSuccess,
                    ),
                    const SizedBox(width: Tokens.space2),
                    Expanded(
                      child: Text(
                        l10n.actionDone,
                        style: app.text.heading.copyWith(
                          color: app.palette.statusSuccess,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              if (flow.busy || flow.step == AuthStep.done)
                AppButton(
                  label: l10n.otpVerify,
                  loading: true,
                  onPressed: null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
