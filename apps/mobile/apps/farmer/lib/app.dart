import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Root widget of the farmer app ("Kisan").
class KisanApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const KisanApp({super.key});

  @override
  ConsumerState<KisanApp> createState() => _KisanAppState();
}

class _KisanAppState extends ConsumerState<KisanApp> {
  StreamSubscription<AppNotification>? _pushes;

  @override
  void initState() {
    super.initState();
    // FA-007: a push that arrives while the app runs opens its screen.
    _pushes = ref.read(pushOpenControllerProvider).stream.listen(_open);
    unawaited(ref.read(pushControllerProvider).listen());
  }

  void _open(AppNotification notification) {
    final route = farmerDeepLink(
      kind: notification.kind,
      route: notification.route,
      data: notification.data,
    );
    if (route != null) ref.read(routerProvider).push(route);
  }

  @override
  void dispose() {
    unawaited(_pushes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => CoreLocalizations.of(context).appNameFarmer,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(settings.themeMode, locale: settings.locale),
      locale: settings.locale,
      localizationsDelegates: CoreLocalizations.localizationsDelegates,
      supportedLocales: CoreLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
