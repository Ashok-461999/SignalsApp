import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_mode.dart';
import '../models/models.dart';
import '../models/news_intel.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/market_mode_switcher.dart';
import '../widgets/status_widgets.dart';
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

    final health = ref.watch(healthProvider);
    final signals = ref.watch(activeSignalsProvider);
    final regimes = ref.watch(regimesProvider);
    final predictions = ref.watch(predictionBySymbolProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: health.when(
            data: (h) {
              final smartApiOk = h.smartapi?['connected'] == true;
              if (h.status == 'ok' && smartApiOk) return const SizedBox.shrink();
              return GlassErrorCard(
                title: h.status == 'ok' ? 'Broker feed reconnecting' : 'Backend degraded',
                message: smartApiOk ? null : 'SmartAPI not connected — signals may be stale',
                onRetry: () => ref.invalidate(healthProvider),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(color: AppColors.accent),
            ),
            error: (e, _) => GlassErrorCard(
              title: 'Server offline',
              message: AppErrorView.friendlyMessage(e),
              onRetry: () {
                ref.invalidate(healthProvider);
                ref.invalidate(activeSignalsProvider);
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: regimes.when(
            data: (r) {
              final regimeMap = r['regimes'] as Map<String, dynamic>? ?? {};
              if (regimeMap.isEmpty) return const SizedBox.shrink();
              final chips = regimeMap.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('Market regime — $chips', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Text('Options signals', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => ref.invalidate(activeSignalsProvider),
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline_rounded),
                  onPressed: () => _showGuide(context),
                ),
              ],
            ),
          ),
        ),
        signals.when(
          data: (list) {
            if (list.isEmpty) {
              return SliverFillRemaining(
                child: _SignalsEmptyState(
                  health: health,
                  onRetry: () {
                    ref.invalidate(healthProvider);
                    ref.invalidate(activeSignalsProvider);
                    ref.invalidate(regimesProvider);
                  },
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
                ...sorted.map((s) => _SignalCard(signal: s, newsOutlook: predictions[s.instrument])),
                const SizedBox(height: 88),
              ]),
            );
          },
          loading: () => const SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.accent),
                  SizedBox(height: 14),
                  Text('Loading evaluations…', style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
          error: (e, _) => SliverFillRemaining(
            child: AppErrorView(
              title: 'Signal feed unavailable',
              message: AppErrorView.friendlyMessage(e),
              onRetry: () => ref.invalidate(activeSignalsProvider),
            ),
          ),
        ),
      ],
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
            _GuideRow(icon: Icons.check_circle_rounded, color: AppColors.profit, text: 'TAKE — buy the option shown (strike + CE/PE) in your broker'),
            _GuideRow(icon: Icons.pause_circle_rounded, color: AppColors.warn, text: 'NO_TRADE — setup fired but skip (bad regime or R:R)'),
            _GuideRow(icon: Icons.nightlight_round, color: AppColors.textMuted, text: 'SIT_OUT — ranging day, avoid buying options'),
            SizedBox(height: 8),
            _GuideRow(icon: Icons.calendar_month_rounded, color: AppColors.accent, text: 'Expiry is 20+ days out (monthly-style) — matches your holding style'),
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
        borderRadius: BorderRadius.circular(16),
        color: active ? AppColors.take : AppColors.surfaceHigh,
        border: Border.all(color: active ? AppColors.takeBorder : AppColors.border),
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
                Text('$total evaluations · options strike & expiry on each card', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal, this.newsOutlook});
  final SignalModel signal;
  final SymbolPrediction? newsOutlook;

  @override
  Widget build(BuildContext context) {
    final d = signal.tradeDecision;
    final accent = decisionAccent(d);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: AlphaSurface(
        accent: accent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SetupDetailScreen(signal: signal)),
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
                    color: accent.withValues(alpha: 0.15),
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
              signal.setupName == 'regime_advisory'
                  ? '${signal.instrument} — market advisory'
                  : '${signal.setupName} · ${signal.instrument}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (signal.optionLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bg.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signal.tradeDecision == 'TAKE' ? 'BUY ${signal.instrument} ${signal.optionLabel}' : signal.optionLabel,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: accent),
                    ),
                    if (signal.suggestedExpiry.isNotEmpty)
                      Text(
                        signal.expiryLabel.isNotEmpty ? 'Expiry ${signal.expiryLabel}' : 'Expiry ${signal.suggestedExpiry}',
                        style: TextStyle(
                          fontSize: 12,
                          color: signal.daysToExpiry >= 20 ? AppColors.textMuted : AppColors.warn,
                        ),
                      ),
                    if (signal.entryPremiumEstimate > 0)
                      Text(
                        'Est. premium ~₹${signal.entryPremiumEstimate.toStringAsFixed(0)} · ${signal.positionSize} lots',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
            ],
            if (signal.direction != 'neutral' && signal.tradeDecision != 'SIT_OUT')
              Text(
                '${signal.direction.toUpperCase()} · R:R ${signal.riskReward.toStringAsFixed(1)}',
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
            if (newsOutlook != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    newsOutlook!.outlook == 'bullish'
                        ? Icons.trending_up_rounded
                        : newsOutlook!.outlook == 'bearish'
                            ? Icons.trending_down_rounded
                            : Icons.remove_rounded,
                    size: 16,
                    color: newsOutlook!.outlook == 'bullish'
                        ? AppColors.profit
                        : newsOutlook!.outlook == 'bearish'
                            ? AppColors.loss
                            : AppColors.warn,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'News: ${newsOutlook!.outlook} (${newsOutlook!.confidence}%) — ${newsOutlook!.optionHint}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ),
                ],
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

class _SignalsEmptyState extends StatelessWidget {
  const _SignalsEmptyState({required this.health, required this.onRetry});

  final AsyncValue<dynamic> health;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = health.hasError;
    final waiting = health.maybeWhen(
      data: (h) => h.status == 'ok',
      orElse: () => false,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.cloud_off_rounded : Icons.radar_rounded,
              size: 56,
              color: offline ? AppColors.loss : AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              offline ? 'Cannot load signals' : 'No option signals yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              offline
                  ? 'Server is offline. Tap Retry — or check Markets tab for live prices.'
                  : waiting
                      ? 'Signals appear at each 5-minute bar close (9:15–15:30 IST).\n\n'
                        'What to do:\n'
                        '• Stay on this tab — TAKE signals show strike + CE/PE\n'
                        '• Check Markets tab for live NIFTY/BANKNIFTY prices\n'
                        '• Ranging days show SIT_OUT — avoid buying options'
                      : 'Connecting to signal engine…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh signals'),
            ),
          ],
        ),
      ),
    );
  }
}
