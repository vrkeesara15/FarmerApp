import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/advisory_widgets.dart';
import '../../widgets/kisan_widgets.dart';

/// F43 Weather (FM-008): the 7-day forecast for the farm with a
/// pictogram, temperature and rain chance, and the spray windows of the
/// next three days as good / avoid blocks with the reason. The cached
/// forecast is shown with "as of" and stays readable offline.
class WeatherScreen extends ConsumerWidget {
  /// Creates the screen.
  const WeatherScreen({this.farmId, super.key});

  /// The farm; the farmer's first farm when null.
  final String? farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    final profile = ref.watch(kisanProfileProvider).value;
    final farm =
        farmId ??
        (profile?.value.farms.isNotEmpty ?? false
            ? profile!.value.farms.first.id
            : null);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.weatherTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: farm == null
                  ? EmptyState(
                      icon: Icons.wb_cloudy_outlined,
                      title: l10n.weatherNone,
                      help: l10n.weatherNoneHelp,
                    )
                  : RefreshOnOpen(
                      onOpen: (ref) => ref
                          .read(advisoryRepositoryProvider)
                          .refreshWeather(farm),
                      child: _Forecast(farmId: farm),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Forecast extends ConsumerWidget {
  const _Forecast({required this.farmId});

  final String farmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final cached = ref.watch(farmWeatherProvider(farmId)).value;
    if (cached == null) {
      return EmptyState(
        icon: Icons.wb_cloudy_outlined,
        title: l10n.weatherNone,
        help: l10n.weatherNoneHelp,
      );
    }
    final weather = cached.value;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(advisoryRepositoryProvider).refreshWeather(farmId),
      child: ListView(
        padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
        children: <Widget>[
          Text(l10n.weatherSevenDays, style: app.text.heading),
          const SizedBox(height: Tokens.space2),
          for (final day in weather.daily.take(7))
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space2),
              child: _DayRow(day: day),
            ),
          const SizedBox(height: Tokens.space3),
          _SpraySection(weather: weather),
          const SizedBox(height: Tokens.space2),
          AsOfLabel(cached.asOf),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final DailyForecast day;

  static String _deg(double v) => v.round().toString();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Container(
      key: Key('weather-day-${isoDay(day.date)}'),
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            weatherIcon(day.weatherCode),
            size: Tokens.space6,
            color: p.primary,
          ),
          const SizedBox(width: Tokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(formatDateIst(day.date), style: app.text.label),
                Text(
                  weatherSky(l10n, day.weatherCode),
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                l10n.weatherTempRange(
                  _deg(day.temperatureMinC),
                  _deg(day.temperatureMaxC),
                ),
                style: app.text.body,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.water_drop_outlined,
                    size: Tokens.space4,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: Tokens.space1),
                  Text(
                    l10n.weatherRainChance(day.precipitationProbabilityPct),
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpraySection extends StatelessWidget {
  const _SpraySection({required this.weather});

  final FarmWeather weather;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final from = weather.spray.all.isEmpty
        ? weather.fetchedAt
        : weather.spray.all.first.start;
    final blocks = weather.spray.blocks(from: from);
    final good = <SprayWindow>[
      for (final w in blocks)
        if (w.isGood(weather.spray.thresholds)) w,
    ];
    return Column(
      key: const Key('spray-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.weatherSprayTitle, style: app.text.heading),
        Text(
          l10n.weatherSprayNextDays,
          style: app.text.caption.copyWith(color: app.palette.textSecondary),
        ),
        const SizedBox(height: Tokens.space2),
        if (good.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space2),
            child: Text(
              l10n.weatherSprayNone,
              key: const Key('spray-none'),
              style: app.text.body,
            ),
          ),
        for (final w in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space2),
            child: _SprayBlock(
              window: w,
              good: w.isGood(weather.spray.thresholds),
              thresholds: weather.spray.thresholds,
            ),
          ),
        const SizedBox(height: Tokens.space1),
        Row(
          key: const Key('spray-advice-only'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.info_outline,
              size: Tokens.space4 + 2,
              color: app.palette.textSecondary,
            ),
            const SizedBox(width: Tokens.space1),
            Expanded(
              child: Text(
                l10n.weatherAdviceOnly,
                style: app.text.caption.copyWith(
                  color: app.palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
        AudioButton(promptId: 'f43_advice_only', text: l10n.weatherAdviceOnly),
      ],
    );
  }
}

class _SprayBlock extends StatelessWidget {
  const _SprayBlock({
    required this.window,
    required this.good,
    required this.thresholds,
  });

  final SprayWindow window;
  final bool good;
  final SprayThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final colour = good ? p.statusSuccess : p.statusWarning;
    final reasons = <String>[
      for (final r in window.blockingReasons(thresholds)) sprayReason(l10n, r),
      for (final c in window.cautions) sprayCaution(l10n, c),
    ];
    return Container(
      key: Key(
        '${good ? 'spray-good' : 'spray-avoid'}-'
        '${window.start.toIso8601String()}',
      ),
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.all(color: colour, width: app.borderWidth + 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            good
                ? Icons.check_circle_outline
                : Icons.do_not_disturb_on_outlined,
            size: Tokens.space6,
            color: colour,
          ),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  good ? l10n.weatherSprayGood : l10n.weatherSprayAvoid,
                  style: app.text.label.copyWith(color: colour),
                ),
                Text(
                  l10n.weatherWindowTime(
                    formatDateTimeIst(window.start),
                    formatTimeIst(window.end),
                  ),
                  style: app.text.body,
                ),
                for (final reason in reasons)
                  Text(
                    reason,
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
