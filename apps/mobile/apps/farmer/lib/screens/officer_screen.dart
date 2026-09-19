import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/kisan_widgets.dart';

/// `tel:` link for an E.164 phone.
String telUri(String phone) => 'tel:$phone';

/// WhatsApp click-to-chat link (`https://wa.me/<digits>`).
String whatsAppUri(String phone) =>
    'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}';

/// F62 My field officer card (FM-011): photo placeholder, name, Call and
/// WhatsApp buttons (`url_launcher`). The name and phone come from the
/// profile's `officer` object (API follow-up); without them the card says
/// "Your field officer" and the buttons are off.
class OfficerScreen extends ConsumerWidget {
  /// Creates the screen.
  const OfficerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final officer = ref.watch(kisanProfileProvider).value?.value.officer;
    final phone = officer?.phone;
    final name = officer?.name;
    final opener = ref.read(urlOpenerProvider);
    Future<void> open(String url) async {
      final ok = await opener.open(url);
      if (!ok && context.mounted) {
        showKisanMessage(context, l10n.kisanCouldNotOpen);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanMyOfficer)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          children: <Widget>[
            Card(
              key: const Key('officer-card'),
              child: Padding(
                padding: const EdgeInsets.all(Tokens.space4),
                child: Column(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: app.tint(p.primaryContainer),
                      child: Text(
                        (name == null || name.isEmpty)
                            ? '?'
                            : name.characters.first.toUpperCase(),
                        style: app.text.display.copyWith(color: p.primary),
                      ),
                    ),
                    const SizedBox(height: Tokens.space3),
                    Text(
                      name ?? l10n.kisanYourOfficer,
                      key: const Key('officer-name'),
                      style: app.text.title,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      l10n.kisanFieldOfficer,
                      style: app.text.body.copyWith(color: p.textSecondary),
                    ),
                    if (phone == null) ...<Widget>[
                      const SizedBox(height: Tokens.space2),
                      Text(
                        l10n.kisanOfficerPhoneMissing,
                        textAlign: TextAlign.center,
                        style: app.text.body.copyWith(color: p.textSecondary),
                      ),
                    ],
                    const SizedBox(height: Tokens.space4),
                    AppButton(
                      key: const Key('officer-call'),
                      label: l10n.kisanCall,
                      icon: Icons.call,
                      onPressed: phone == null
                          ? null
                          : () => open(telUri(phone)),
                    ),
                    const SizedBox(height: Tokens.space2),
                    AppButton(
                      key: const Key('officer-whatsapp'),
                      label: l10n.kisanWhatsApp,
                      icon: Icons.chat_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: phone == null
                          ? null
                          : () => open(whatsAppUri(phone)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
