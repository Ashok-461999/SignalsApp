import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_mode.dart';
import '../providers/app_providers.dart';
import '../screens/chart_screen.dart';
import '../screens/crypto_watchlist_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/candlestick_chart.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  static const _indices = [
    ('NIFTY', 'NSE 50', Icons.show_chart_rounded),
    ('BANKNIFTY', 'Bank index', Icons.account_balance_rounded),
    ('SENSEX', 'BSE 30', Icons.trending_up_rounded),
  ];

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

    final prices = ref.watch(livePricesProvider);
    final health = ref.watch(healthProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                const Text('Indian indices', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const Spacer(),
                health.when(
                  data: (h) => _LiveBadge(live: h.status == 'ok'),
                  loading: () => const _LiveBadge(live: false),
                  error: (_, __) => const _LiveBadge(live: false),
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
                final (name, subtitle, icon) = _indices[i];
                return _IndexCard(
                  name: name,
                  subtitle: subtitle,
                  icon: icon,
                  price: prices.maybeWhen(data: (p) => p[name], orElse: () => null),
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
      ],
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
    required this.price,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final double? price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candles = ref.watch(candlesProvider((name, '5m')));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surfaceHigh.withValues(alpha: 0.5),
                  AppColors.surface,
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
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
                      const SizedBox(height: 4),
                      Text(
                        price != null ? price!.toStringAsFixed(2) : '—',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                candles.when(
                  data: (d) => MiniSparkline(candles: d.candles),
                  loading: () => const SizedBox(width: 88, height: 40),
                  error: (_, __) => const Icon(Icons.candlestick_chart_rounded, color: AppColors.textMuted),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
