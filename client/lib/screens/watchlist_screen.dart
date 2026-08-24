import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_mode.dart';
import '../models/news_intel.dart';
import '../providers/app_providers.dart';
import '../screens/chart_screen.dart';
import '../screens/crypto_watchlist_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/status_widgets.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  static const _indices = [
    ('NIFTY', 'NSE 50', Icons.show_chart_rounded),
    ('BANKNIFTY', 'Bank index', Icons.account_balance_rounded),
    ('FINNIFTY', 'Fin services', Icons.pie_chart_rounded),
    ('SENSEX', 'BSE 30', Icons.trending_up_rounded),
  ];

  void _refresh(WidgetRef ref) {
    ref.invalidate(healthProvider);
    ref.invalidate(candlesProvider);
    ref.invalidate(marketIntelProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(marketModeProvider);
    if (mode == MarketMode.crypto) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Crypto markets', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          Expanded(child: CryptoWatchlistScreen()),
        ],
      );
    }

    final health = ref.watch(healthProvider);
    final predictions = ref.watch(predictionBySymbolProvider);

    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: health.when(
              data: (h) {
                final smartOk = h.smartapi?['connected'] == true;
                final paper = h.trading?['paper_trading'] as bool? ?? true;
                return MarketDashboard(
                  serverOk: h.status == 'ok',
                  smartApiOk: smartOk,
                  paperMode: paper,
                  onRetry: () => _refresh(ref),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => GlassErrorCard(
                title: 'Server offline',
                message: AppErrorView.friendlyMessage(e),
                onRetry: () => _refresh(ref),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Text('Indian indices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  health.maybeWhen(
                    data: (h) => _LiveBadge(live: h.status == 'ok'),
                    orElse: () => const _LiveBadge(live: false),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final (name, subtitle, icon) = _indices[i];
                  return _IndexCard(
                    name: name,
                    subtitle: subtitle,
                    icon: icon,
                    outlook: predictions[name],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChartScreen(instrument: name)),
                    ),
                  );
                },
                childCount: _indices.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Text('F&O stocks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => ref.invalidate(marketIntelProvider),
                    child: const Text('News outlook'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final stock = indianFnoStocks[i];
                  return _FnoStockCard(
                    stock: stock,
                    outlook: predictions[stock.symbol],
                    onTap: () => _showStockIntel(context, stock, predictions[stock.symbol]),
                  );
                },
                childCount: indianFnoStocks.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStockIntel(BuildContext context, FnoStock stock, SymbolPrediction? outlook) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${stock.symbol} · ${stock.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (outlook != null) ...[
              Text('News outlook: ${outlook.outlook.toUpperCase()} (${outlook.confidence}%)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(outlook.optionHint, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(outlook.prediction, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ] else
              const Text(
                'No live headlines matched this stock yet. Check Intel tab for market-wide news.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            const SizedBox(height: 12),
            const Text(
              'Options signals run on NIFTY, BANKNIFTY, FINNIFTY & SENSEX. Stock outlook is news-based.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.live});
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (live ? AppColors.profit : AppColors.loss).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: live ? AppColors.profit : AppColors.loss),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: live ? AppColors.profit : AppColors.loss),
          const SizedBox(width: 6),
          Text(
            live ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: live ? AppColors.profit : AppColors.loss,
            ),
          ),
        ],
      ),
    );
  }
}

class _IndexCard extends ConsumerWidget {
  const _IndexCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.outlook,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final SymbolPrediction? outlook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candles = ref.watch(candlesProvider((name, '5m')));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AlphaSurface(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, color: AppColors.accent, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  if (outlook != null) ...[
                    const SizedBox(height: 4),
                    _OutlookChip(outlook: outlook!.outlook, confidence: outlook!.confidence),
                  ],
                  const SizedBox(height: 6),
                  _LivePriceText(name: name),
                ],
              ),
            ),
            RepaintBoundary(
              child: candles.when(
                data: (d) => MiniSparkline(candles: d.candles),
                loading: () => const SizedBox(width: 88, height: 40),
                error: (_, __) => const Icon(Icons.candlestick_chart_rounded, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _FnoStockCard extends StatelessWidget {
  const _FnoStockCard({required this.stock, required this.onTap, this.outlook});

  final FnoStock stock;
  final VoidCallback onTap;
  final SymbolPrediction? outlook;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AlphaSurface(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stock.symbol, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(stock.name, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (outlook != null)
              _OutlookChip(outlook: outlook!.outlook, confidence: outlook!.confidence)
            else
              const Text('—', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _OutlookChip extends StatelessWidget {
  const _OutlookChip({required this.outlook, required this.confidence});

  final String outlook;
  final int confidence;

  @override
  Widget build(BuildContext context) {
    final color = switch (outlook) {
      'bullish' => AppColors.profit,
      'bearish' => AppColors.loss,
      _ => AppColors.warn,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${outlook.toUpperCase()} $confidence%',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _LivePriceText extends ConsumerWidget {
  const _LivePriceText({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = ref.watch(
      livePricesProvider.select(
        (async) => async.maybeWhen(data: (p) => p[name], orElse: () => null),
      ),
    );

    return Text(
      price != null ? '₹${price.toStringAsFixed(2)}' : 'Awaiting feed…',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: price != null ? AppColors.textPrimary : AppColors.textMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
