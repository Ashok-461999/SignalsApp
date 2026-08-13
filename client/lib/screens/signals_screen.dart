import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_mode.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/market_mode_switcher.dart';
import 'setup_detail_screen.dart';

class SignalsScreen extends ConsumerWidget {
  const SignalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(marketModeProvider);
    if (mode == MarketMode.crypto) {
      return const CustomScrollView(
        slivers: [
          SliverFillRemaining(
            child: CryptoComingSoon(
              title: 'Crypto signals coming soon',
              subtitle: 'ORB, trend & breakout setups for BTC, ETH & majors — same engine, 24/7 market.',
            ),
          ),
        ],
      );
    }

    final signals = ref.watch(activeSignalsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Signals'),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline_rounded),
                onPressed: () => _showGuide(context),
              ),
            ],
          ),
          signals.when(
            data: (list) {
              if (list.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.radar_rounded, size: 56, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('Scanning market…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text('Signals appear on 5m bar close', style: TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                );
              }

              final takeCount = list.where((s) => s.tradeDecision == 'TAKE').length;
              final sorted = [...list]..sort((a, b) {
                  const order = {'TAKE': 0, 'NO_TRADE': 1, 'SIT_OUT': 2};
                  return (order[a.tradeDecision] ?? 9).compareTo(order[b.tradeDecision] ?? 9);
                });

              return SliverList(
                delegate: SliverChildListDelegate([
                  _HeroBanner(takeCount: takeCount, total: list.length),
                  ...sorted.map((s) => _SignalCard(signal: s)),
                  const SizedBox(height: 88),
                ]),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
            ),
            error: (e, _) => SliverFillRemaining(child: Center(child: Text('WS: $e'))),
          ),
        ],
      ),
    );
  }

  void _showGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How to read signals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 16),
            _GuideRow(icon: Icons.check_circle_rounded, color: AppColors.profit, text: 'TAKE — valid setup, trade in broker'),
            _GuideRow(icon: Icons.pause_circle_rounded, color: AppColors.warn, text: 'NO_TRADE — fired but skip (regime/R:R)'),
            _GuideRow(icon: Icons.nightlight_round, color: AppColors.textMuted, text: 'SIT_OUT — ranging day, no directional buys'),
          ],
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.takeCount, required this.total});
  final int takeCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final active = takeCount > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: active
              ? [AppColors.take, AppColors.surfaceHigh]
              : [AppColors.noTrade, AppColors.surfaceHigh],
        ),
        border: Border.all(color: active ? AppColors.takeBorder : AppColors.noTradeBorder),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.bolt_rounded : Icons.hourglass_empty_rounded,
            color: active ? AppColors.profit : AppColors.warn,
            size: 36,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? '$takeCount tradeable setup(s)' : 'No TAKE signals',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Text('$total evaluations · tap for chart & AI', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal});
  final SignalModel signal;

  @override
  Widget build(BuildContext context) {
    final d = signal.tradeDecision;
    final accent = decisionAccent(d);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: decisionSurface(d),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SetupDetailScreen(signal: signal)),
          ),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: decisionBorder(d)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(d, style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                    const Spacer(),
                    if (signal.regime.isNotEmpty)
                      Text(signal.regime, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${signal.setupName} · ${signal.instrument}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                if (signal.direction != 'neutral')
                  Text(
                    '${signal.direction.toUpperCase()} · R:R ${signal.riskReward.toStringAsFixed(1)} · ${signal.positionSize} lots',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                if (signal.decisionReason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    signal.decisionReason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _pill('E ${signal.underlyingEntry.toStringAsFixed(0)}'),
                    const SizedBox(width: 6),
                    _pill('SL ${signal.underlyingStopLoss.toStringAsFixed(0)}', color: AppColors.loss),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.textMuted),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color ?? AppColors.textPrimary, fontWeight: FontWeight.w600)),
      );
}
