import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Root widget of the field agent app ("Mitra").
class MitraApp extends ConsumerWidget {
  /// Creates the app.
  const MitraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => CoreLocalizations.of(context).appNameAgent,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(settings.themeMode, locale: settings.locale),
      locale: settings.locale,
      localizationsDelegates: CoreLocalizations.localizationsDelegates,
      supportedLocales: CoreLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
