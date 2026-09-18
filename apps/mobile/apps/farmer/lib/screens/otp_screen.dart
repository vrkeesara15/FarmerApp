import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

/// F03 OTP entry with resend timer.
class OtpScreen extends ConsumerWidget {
  /// Creates the screen.
  const OtpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final flow = ref.watch(authFlowProvider);
    final notifier = ref.read(authFlowProvider.notifier);
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
                    Text(
                      l10n.actionDone,
                      style: app.text.heading.copyWith(
                        color: app.palette.statusSuccess,
                      ),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              if (flow.busy)
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
