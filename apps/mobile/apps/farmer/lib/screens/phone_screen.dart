import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

/// F02 Phone login (+91); the only typing a farmer does besides the OTP (NF-010).
class PhoneScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final TextEditingController _phone = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref.read(authFlowProvider.notifier).requestOtp(_phone.text);
    if (!mounted) return;
    if (ref.read(authFlowProvider).step == AuthStep.otp) {
      context.go(AppRoutes.otp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final flow = ref.watch(authFlowProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appNameFarmer),
        leading: BackButton(onPressed: () => context.go(AppRoutes.language)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l10n.phoneLoginTitle, style: app.text.title),
              const SizedBox(height: Tokens.space6),
              AppTextField(
                label: l10n.phoneLabel,
                controller: _phone,
                indiaPhone: true,
                autofocus: true,
                helperText: l10n.phoneHelper,
                errorText: flow.phoneError ? authFailureText(l10n, flow) : null,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const Spacer(),
              AppButton(
                label: l10n.phoneSendOtp,
                icon: Icons.sms_outlined,
                loading: flow.busy,
                onPressed: flow.locked ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
