import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';

/// F60 QR path (FM-011): the officer shows a QR (A32); the farmer scans it
/// with the camera (`mobile_scanner`), the token names the visit, and F61
/// rating posts it to `/v1/visits/{id}/farmer-confirm`.
class VisitScanScreen extends ConsumerWidget {
  /// Creates the screen.
  const VisitScanScreen({super.key});

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final l10n = CoreLocalizations.of(context);
    final raw = await ref.read(barcodeScannerProvider).scan(context);
    if (!context.mounted || raw == null) return;
    final token = ConfirmToken.decode(raw);
    if (token == null) {
      showKisanMessage(context, l10n.kisanScanNotVisitQr);
      return;
    }
    context.pushReplacement(AppRoutes.visitRate(token.visitId), extra: token);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanScanTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: Tokens.space6),
              Icon(Icons.qr_code_scanner, size: 96, color: p.primary),
              const SizedBox(height: Tokens.space4),
              SpokenText(
                promptId: 'f60_scan',
                text: l10n.kisanScanHelp,
                style: app.text.heading,
              ),
              const Spacer(),
              AppButton(
                key: const Key('visit-scan'),
                label: l10n.kisanScanButton,
                icon: Icons.qr_code_scanner,
                onPressed: () => _scan(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
