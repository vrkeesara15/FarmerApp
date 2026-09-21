import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/kisan_widgets.dart';

/// F45 Mandi prices (FM-012), opened from F40 My crops.
///
/// One card per crop the farmer grows, each listing the nearest markets with
/// the modal price per quintal. Every card carries **the date the mandi
/// published the figure and the name of the source** — FM-012 is graded on
/// exactly that — and the screen ends with a plain-language note that the
/// prices are indicative, plus the usual "as of" for the offline cache.
///
/// Two dates, deliberately: the price date belongs to the mandi, the "as of"
/// belongs to this phone. A week-old cache never looks like today's price.
class MandiPricesScreen extends ConsumerWidget {
  /// Creates the screen.
  const MandiPricesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = CoreLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mandiTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: RefreshOnOpen(
                onOpen: (ref) =>
                    ref.read(marketRepositoryProvider).refreshPrices(),
                child: const _Prices(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Prices extends ConsumerWidget {
  const _Prices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final cached = ref.watch(mandiPricesProvider).value;
    if (cached == null) {
      return EmptyState(
        icon: Icons.storefront_outlined,
        title: l10n.mandiEmptyTitle,
        help: l10n.mandiEmptyHelp,
      );
    }
    final prices = cached.value;
    if (prices.crops.isEmpty) {
      return EmptyState(
        icon: Icons.storefront_outlined,
        title: l10n.mandiEmptyTitle,
        help: l10n.mandiEmptyHelp,
      );
    }
    final language = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
      children: <Widget>[
        for (final crop in prices.crops)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space3),
            child: _CropCard(crop: crop, language: language),
          ),
        const SizedBox(height: Tokens.space2),
        Row(
          key: const Key('mandi-indicative'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.info_outline,
              size: Tokens.space4 + 2,
              color: app.palette.textSecondary,
            ),
            const SizedBox(width: Tokens.space2),
            Expanded(
              child: Text(
                l10n.mandiIndicative,
                style: app.text.caption.copyWith(
                  color: app.palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.space2),
        AudioButton(promptId: 'f45_indicative', text: l10n.mandiIndicative),
        const SizedBox(height: Tokens.space2),
        AsOfLabel(cached.asOf),
        const SizedBox(height: Tokens.space8),
      ],
    );
  }
}

class _CropCard extends StatelessWidget {
  const _CropCard({required this.crop, required this.language});

  final CropPrices crop;
  final String language;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final date = crop.priceDate;
    return KisanCard(
      key: Key('mandi-crop-${crop.cropCode}'),
      title: crop.name(language),
      icon: Icons.grass_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (crop.isEmpty || date == null)
            Text(
              l10n.mandiNoPriceYet,
              style: app.text.body.copyWith(color: app.palette.textSecondary),
            )
          else ...<Widget>[
            // FM-012 acceptance: the date and the source sit with the price.
            Text(l10n.mandiPriceOn(formatDateIst(date)), style: app.text.label),
            if (crop.sourceName != null)
              Text(
                l10n.mandiSource(crop.sourceName!),
                style: app.text.caption.copyWith(
                  color: app.palette.textSecondary,
                ),
              ),
            const SizedBox(height: Tokens.space2),
            for (final quote in crop.quotes)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.space2),
                child: _QuoteRow(quote: quote),
              ),
          ],
        ],
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote});

  final MandiQuote quote;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(quote.market, style: app.text.body),
                Text(
                  l10n.mandiRange(
                    formatInr(quote.minPricePaise),
                    formatInr(quote.maxPricePaise),
                  ),
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.space2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatInr(quote.modalPricePaise),
                style: app.text.heading.copyWith(color: p.primary),
              ),
              Text(
                l10n.mandiPerQuintal,
                style: app.text.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
