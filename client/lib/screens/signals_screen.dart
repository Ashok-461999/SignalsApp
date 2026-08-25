import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../models/news_intel.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/status_widgets.dart';
import 'setup_detail_screen.dart';

class SignalsScreen extends ConsumerStatefulWidget {
  const SignalsScreen({super.key});

  @override
  ConsumerState<SignalsScreen> createState() => _SignalsScreenState();
}

enum _SignalFilter { all, take, noTrade, sitOut }

class _SignalsScreenState extends ConsumerState<SignalsScreen> {
  _SignalFilter _filter = _SignalFilter.all;

  List<SignalModel> _applyFilter(List<SignalModel> list) => switch (_filter) {
        _SignalFilter.take => list.where((s) => s.tradeDecision == 'TAKE').toList(),
        _SignalFilter.noTrade => list.where((s) => s.tradeDecision == 'NO_TRADE').toList(),
        _SignalFilter.sitOut => list.where((s) => s.tradeDecision == 'SIT_OUT').toList(),
        _ => list,
      };

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(healthProvider);
    final signals = ref.watch(activeSignalsProvider);
    final regimes = ref.watch(regimesProvider);
    final predictions = ref.watch(predictionBySymbolProvider);
    final intel = ref.watch(marketIntelProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: intel.when(
            data: (data) => data.giftNifty.available
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _GiftNiftyBanner(gift: data.giftNifty),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
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
                const Text('Trade signals', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _DecisionFilterChip(
                    label: 'All',
                    selected: _filter == _SignalFilter.all,
                    onTap: () => setState(() => _filter = _SignalFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _DecisionFilterChip(
                    label: 'TAKE',
                    color: AppColors.profit,
                    selected: _filter == _SignalFilter.take,
                    onTap: () => setState(() => _filter = _SignalFilter.take),
                  ),
                  const SizedBox(width: 8),
                  _DecisionFilterChip(
                    label: 'NO_TRADE',
                    color: AppColors.warn,
                    selected: _filter == _SignalFilter.noTrade,
                    onTap: () => setState(() => _filter = _SignalFilter.noTrade),
                  ),
                  const SizedBox(width: 8),
                  _DecisionFilterChip(
                    label: 'SIT_OUT',
                    selected: _filter == _SignalFilter.sitOut,
                    onTap: () => setState(() => _filter = _SignalFilter.sitOut),
                  ),
                ],
              ),
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
            final filtered = _applyFilter(list);
            final sorted = [...filtered]..sort((a, b) {
                const order = {'TAKE': 0, 'NO_TRADE': 1, 'SIT_OUT': 2};
                return (order[a.tradeDecision] ?? 9).compareTo(order[b.tradeDecision] ?? 9);
              });

            if (filtered.isEmpty) {
              final filterLabel = switch (_filter) {
                _SignalFilter.take => 'TAKE',
                _SignalFilter.noTrade => 'NO_TRADE',
                _SignalFilter.sitOut => 'SIT_OUT',
                _ => 'matching',
              };
              return SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No $filterLabel signals — try another filter',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              );
            }

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
            _GuideRow(icon: Icons.pause_circle_rounded, color: AppColors.warn, text: 'NO_TRADE — FVG/sweep fired but skip (bad regime or R:R)'),
            _GuideRow(icon: Icons.nightlight_round, color: AppColors.textMuted, text: 'SIT_OUT — ranging day, avoid buying options'),
            SizedBox(height: 8),
            _GuideRow(icon: Icons.candlestick_chart_rounded, color: AppColors.accent, text: 'Setups: FVG retest & liquidity sweep (not EMA) + news on Intel tab'),
            _GuideRow(icon: Icons.calendar_month_rounded, color: AppColors.accent, text: 'Expiry is 20+ days out (monthly-style) — matches your holding style'),
          ],
        ),
      ),
    );
  }
}

class _GiftNiftyBanner extends StatelessWidget {
  const _GiftNiftyBanner({required this.gift});
  final GiftNiftyInsight gift;

  @override
  Widget build(BuildContext context) {
    final negative = gift.predictedNiftyOpen == 'negative';
    final positive = gift.predictedNiftyOpen == 'positive';
    final color = negative ? AppColors.loss : positive ? AppColors.profit : AppColors.warn;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            negative ? Icons.trending_down_rounded : positive ? Icons.trending_up_rounded : Icons.horizontal_rule_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              gift.summary,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionFilterChip extends StatelessWidget {
  const _DecisionFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.accent;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: selected ? accent : AppColors.textMuted,
      ),
      selectedColor: accent.withValues(alpha: 0.18),
      backgroundColor: AppColors.surfaceHigh.withValues(alpha: 0.5),
      side: BorderSide(color: selected ? accent.withValues(alpha: 0.5) : AppColors.border),
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
                Text('$total evaluations · BUY = option to buy · LONG/SHORT = bias', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
    final isTake = d == 'TAKE';
    final dir = signal.directionLabel;
    final dirColor = dir == 'LONG'
        ? AppColors.profit
        : dir == 'SHORT'
            ? AppColors.loss
            : AppColors.textMuted;

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
                _badge(d, accent),
                if (dir != 'NEUTRAL') ...[
                  const SizedBox(width: 6),
                  _badge(dir, dirColor),
                ],
                const Spacer(),
                if (signal.regime.isNotEmpty)
                  Text(signal.regime, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
            if (signal.freshnessLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                signal.freshnessLabel!,
                style: TextStyle(
                  fontSize: 10,
                  color: signal.isStale ? AppColors.warn : AppColors.textMuted,
                  fontWeight: signal.isStale ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              signal.setupName == 'regime_advisory'
                  ? '${signal.instrument} — market advisory'
                  : '${signal.setupName} · ${signal.instrument}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (signal.actionLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bg.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: (isTake ? accent : AppColors.border).withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signal.actionLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isTake ? accent : AppColors.textMuted,
                      ),
                    ),
                    if (signal.profitSummary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        signal.profitSummary,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isTake ? AppColors.profit : AppColors.textMuted,
                        ),
                      ),
                    ],
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
                    if (signal.ivWarning != null)
                      Text(signal.ivWarning!, style: const TextStyle(fontSize: 11, color: AppColors.warn)),
                    if (signal.dteWarning != null)
                      Text(signal.dteWarning!, style: const TextStyle(fontSize: 11, color: AppColors.warn)),
                    if (isTake && signal.brokerOrderHint.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: signal.brokerOrderHint));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied — paste in your broker app')),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy order'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (signal.decisionReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(signal.decisionReason, style: const TextStyle(fontSize: 13, height: 1.35)),
            ],
            if (newsOutlook != null) ...[
              const SizedBox(height: 8),
              if (newsOutlook!.whyBullish.isNotEmpty || newsOutlook!.whyBearish.isNotEmpty) ...[
                if (newsOutlook!.whyBullish.isNotEmpty)
                  Text(
                    '↑ ${newsOutlook!.whyBullish.first}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.profit),
                  ),
                if (newsOutlook!.whyBearish.isNotEmpty)
                  Text(
                    '↓ ${newsOutlook!.whyBearish.first}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.loss),
                  ),
                const SizedBox(height: 4),
              ],
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
                if (signal.underlyingTarget.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _pill('T ${signal.underlyingTarget.first.toStringAsFixed(0)}', color: AppColors.profit),
                ],
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      );

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
