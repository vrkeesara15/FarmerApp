import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Root widget of the field agent app (working name "Mitra"; FA-008: the
/// tenant's own name, colour and logo replace it at run time).
class MitraApp extends ConsumerWidget {
  /// Creates the app.
  const MitraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final brand = ref.watch(appBrandProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => brand.name(CoreLocalizations.of(context)),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
        settings.themeMode,
        locale: settings.locale,
        brand: brand,
      ),
      locale: settings.locale,
      localizationsDelegates: CoreLocalizations.localizationsDelegates,
      supportedLocales: CoreLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
