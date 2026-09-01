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

enum _SignalsViewTab { live, history }

class _SignalsScreenState extends ConsumerState<SignalsScreen> {
  _SignalFilter _filter = _SignalFilter.all;
  _SignalsViewTab _viewTab = _SignalsViewTab.live;

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
    final alphaSignals = ref.watch(alphaSignalsProvider);
    final history = ref.watch(signalHistoryProvider);
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
                  onPressed: () {
                    ref.invalidate(activeSignalsProvider);
                    ref.invalidate(signalHistoryProvider);
                    ref.invalidate(alphaSignalsProvider);
                  },
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
          child: alphaSignals.when(
            data: (data) {
              final list = (data['signals'] as List<dynamic>? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              if (list.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alpha Engine (${data['count'] ?? list.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    ...list.take(3).map((sig) => _AlphaSignalCard(signal: sig)),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<_SignalsViewTab>(
                    segments: const [
                      ButtonSegment(value: _SignalsViewTab.live, label: Text('Live')),
                      ButtonSegment(value: _SignalsViewTab.history, label: Text('History')),
                    ],
                    selected: {_viewTab},
                    onSelectionChanged: (s) => setState(() => _viewTab = s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_viewTab == _SignalsViewTab.live)
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
        if (_viewTab == _SignalsViewTab.history)
          history.when(
            data: (data) => SliverList(
              delegate: SliverChildListDelegate([
                _HistorySummaryBanner(summary: data.summary),
                ...data.items.map((item) => _HistoryCard(item: item)),
                const SizedBox(height: 88),
              ]),
            ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
            ),
            error: (e, _) => SliverFillRemaining(
              child: AppErrorView(
                title: 'History unavailable',
                message: AppErrorView.friendlyMessage(e),
                onRetry: () => ref.invalidate(signalHistoryProvider),
              ),
            ),
          )
        else
          signals.when(
          data: (list) {
            if (list.isEmpty) {
              return SliverFillRemaining(
                child: _SignalsEmptyState(
                  health: health,
                  regimes: regimes,
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
            _GuideRow(icon: Icons.science_rounded, color: AppColors.accent, text: 'Backtest banner — profitable setups only get CAN TAKE'),
            _GuideRow(icon: Icons.check_circle_rounded, color: AppColors.profit, text: 'OPTIONS (primary) — buy strike + CE/PE for higher profit'),
            _GuideRow(icon: Icons.show_chart_rounded, color: AppColors.accent, text: 'FUTURES (backup) — if option SL hits but index keeps moving'),
            _GuideRow(icon: Icons.pause_circle_rounded, color: AppColors.warn, text: 'NO_TRADE — setup fired but skip (bad regime or R:R)'),
            _GuideRow(icon: Icons.nightlight_round, color: AppColors.textMuted, text: 'SIT_OUT — ranging day, avoid buying options'),
            SizedBox(height: 8),
            _GuideRow(icon: Icons.candlestick_chart_rounded, color: AppColors.accent, text: 'Setups: FVG retest & liquidity sweep (not EMA) + news on Intel tab'),
            _GuideRow(icon: Icons.calendar_month_rounded, color: AppColors.accent, text: 'Weekly ATM options for scalp — small index move, bigger premium gain'),
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
                Text('$total evaluations · OPTIONS primary · FUTURES backup', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
                if (signal.canTake) ...[
                  const SizedBox(width: 6),
                  _badge('CAN TAKE ${signal.takeConfidence}%', AppColors.profit),
                ] else if (signal.prediction.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      signal.prediction,
                      style: const TextStyle(fontSize: 10, color: AppColors.warn),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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
            if (signal.backtestSummary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: (signal.backtestOk ? AppColors.profit : signal.backtestFailed ? AppColors.loss : AppColors.warn)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (signal.backtestOk ? AppColors.profit : signal.backtestFailed ? AppColors.loss : AppColors.warn)
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      signal.backtestOk ? Icons.verified_rounded : Icons.warning_amber_rounded,
                      size: 16,
                      color: signal.backtestOk ? AppColors.profit : signal.backtestFailed ? AppColors.loss : AppColors.warn,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        signal.backtestSummary,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: signal.backtestOk ? AppColors.profit : signal.backtestFailed ? AppColors.loss : AppColors.warn,
                        ),
                      ),
                    ),
                  ],
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
                    if (isTake && signal.dualLegNote.isNotEmpty) ...[
                      Text(
                        signal.dualLegNote,
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (isTake && signal.actionLabel.isNotEmpty) ...[
                      const Text(
                        'OPTIONS · PRIMARY',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.profit),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        signal.actionLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isTake ? accent : AppColors.textMuted,
                        ),
                      ),
                    ] else
                      Text(
                        signal.actionLabel.isNotEmpty ? signal.actionLabel : signal.directionLabel,
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
                    if (isTake && signal.slHit) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.loss.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.loss.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          signal.liveStatusLabel.isNotEmpty
                              ? signal.liveStatusLabel
                              : 'STRICT SL HIT — exit if premium below ₹${signal.premiumStop.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.loss),
                        ),
                      ),
                    ],
                    if (isTake && signal.optionTradePlan.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.profit.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.profit.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'OPTION PRICES (scalp)',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.profit),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              signal.optionTradePlan,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                            if (signal.premiumEntry > 0)
                              Text(
                                'Buy ₹${signal.premiumEntry.toStringAsFixed(0)} → Target ₹${signal.premiumTarget.toStringAsFixed(0)} · STRICT SL ₹${signal.premiumStop.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                            if (signal.optionTradePlanEn.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                signal.optionTradePlanEn,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.profit),
                              ),
                            ],
                            if (signal.expectedProfitInr > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Expected profit ~₹${signal.expectedProfitInr.toStringAsFixed(0)} on ${signal.positionSize > 0 ? signal.positionSize : 1} lot(s) · exit if premium < ₹${signal.premiumStop.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.profit),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (signal.entryPremiumEstimate > 0 && signal.optionTradePlan.isEmpty)
                      Text(
                        'Est. premium ~₹${signal.entryPremiumEstimate.toStringAsFixed(0)} · ${signal.positionSize} lots',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    if (signal.maxLossInr > 0)
                      Text(
                        'Max loss ~₹${signal.maxLossInr.toStringAsFixed(0)}'
                        '${signal.premiumRequiredInr > 0 ? ' · need ~₹${signal.premiumRequiredInr.toStringAsFixed(0)}' : ''}'
                        '${signal.capitalInr > 0 ? ' (₹${signal.capitalInr.toStringAsFixed(0)} capital)' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: signal.canTake ? AppColors.profit : AppColors.warn,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (signal.holdHint.isNotEmpty)
                      Text(
                        signal.holdHint,
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    if (isTake && signal.hasFuturesLeg) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'FUTURES · BACKUP',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accent),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        signal.futuresCanTake
                            ? '${signal.futuresActionLabel} × ${signal.futuresLots} lots'
                            : signal.futuresActionLabel,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      if (signal.futuresCanTake && signal.futuresMaxLossInr > 0)
                        Text(
                          'Max loss ~₹${signal.futuresMaxLossInr.toStringAsFixed(0)} · margin ~₹${signal.futuresMarginInr.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        )
                      else if (signal.futuresReason.isNotEmpty)
                        Text(
                          signal.futuresReason,
                          style: const TextStyle(fontSize: 11, color: AppColors.warn),
                        )
                      else if (signal.futuresMarginPerLotInr > 0)
                        Text(
                          'Margin ~₹${signal.futuresMarginPerLotInr.toStringAsFixed(0)}/lot — options preferred on small capital',
                          style: const TextStyle(fontSize: 11, color: AppColors.warn),
                        ),
                    ],
                    if (signal.ivWarning != null)
                      Text(signal.ivWarning!, style: const TextStyle(fontSize: 11, color: AppColors.warn)),
                    if (signal.dteWarning != null)
                      Text(signal.dteWarning!, style: const TextStyle(fontSize: 11, color: AppColors.warn)),
                    if (isTake && signal.brokerOrderHint.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: signal.combinedBrokerHint.isNotEmpty ? signal.combinedBrokerHint : signal.brokerOrderHint));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied — paste in your broker app')),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(signal.hasFuturesLeg ? 'Copy options + futures' : 'Copy order'),
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
            if (signal.liveTrades >= 3) ...[
              const SizedBox(height: 6),
              Text(
                'Live track: ${signal.liveWinRate.toStringAsFixed(0)}% win (${signal.liveWins}W/${signal.liveLosses}L)'
                '${signal.liveMaxDrawdownInr > 0 ? ' · max DD ₹${signal.liveMaxDrawdownInr.toStringAsFixed(0)}' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: signal.liveWinRate >= 50 ? AppColors.profit : AppColors.warn,
                ),
              ),
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

class _HistorySummaryBanner extends StatelessWidget {
  const _HistorySummaryBanner({required this.summary});
  final SignalHistorySummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: AlphaSurface(
        accent: AppColors.accent,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tracked results · ${summary.takeSignals} TAKE',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                if (summary.takeOptionsWinRate > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.profit.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${summary.takeOptionsWinRate.toStringAsFixed(0)}% win',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.profit),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'W ${summary.takeOptionsWins} · L ${summary.takeOptionsFails} · Open ${summary.takeOptionsOpen}'
              '${summary.takeTotalPnlInr != 0 ? ' · P&L ₹${summary.takeTotalPnlInr.toStringAsFixed(0)}' : ''}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            if (summary.takeMaxDrawdownInr > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Max drawdown ₹${summary.takeMaxDrawdownInr.toStringAsFixed(0)} (options)',
                style: const TextStyle(fontSize: 11, color: AppColors.warn, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _summaryTile(
                    'Options',
                    '${summary.takeOptionsWins} WIN',
                    '${summary.takeOptionsFails} FAIL',
                    AppColors.profit,
                    AppColors.loss,
                    subtitle: '${summary.takeOptionsWinRate.toStringAsFixed(0)}%',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _summaryTile(
                    'Futures',
                    '${summary.futuresProfit} profit',
                    '${summary.futuresSlHit} SL',
                    AppColors.profit,
                    AppColors.loss,
                    subtitle: '${summary.takeFuturesWinRate.toStringAsFixed(0)}%',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(String title, String wins, String losses, Color winColor, Color lossColor, {String subtitle = ''}) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.bg.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                if (subtitle.isNotEmpty) ...[
                  const Spacer(),
                  Text(subtitle, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: winColor)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(wins, style: TextStyle(fontSize: 11, color: winColor, fontWeight: FontWeight.w700)),
            Text(losses, style: TextStyle(fontSize: 11, color: lossColor, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});
  final SignalHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final s = item.signal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: AlphaSurface(
        accent: decisionAccent(s.tradeDecision),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupDetailScreen(signal: s))),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(s.tradeDecision, style: TextStyle(fontWeight: FontWeight.w800, color: decisionAccent(s.tradeDecision))),
                if (item.optionsVerdict.isNotEmpty && item.optionsVerdict != '—') ...[
                  const SizedBox(width: 8),
                  _verdictBadge(item.optionsVerdict),
                ],
                const SizedBox(width: 8),
                if (s.directionLabel != 'NEUTRAL')
                  Text(s.directionLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.directionLabel == 'LONG' ? AppColors.profit : AppColors.loss)),
                const Spacer(),
                Text(_shortTime(item.loggedAt), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${s.setupName} · ${s.instrument}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (s.actionLabel.isNotEmpty)
              Text(s.actionLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            if (s.premiumEntry > 0)
              Text(
                'Premium ₹${s.premiumEntry.toStringAsFixed(0)} → ₹${s.premiumTarget.toStringAsFixed(0)} · SL ₹${s.premiumStop.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            if (item.optionsResult.isSlHit && s.premiumStop > 0)
              Text(
                'STRICT SL hit — premium went below ₹${s.premiumStop.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.loss),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _ResultColumn(title: 'Options', result: item.optionsResult, isOptions: true)),
                const SizedBox(width: 10),
                Expanded(child: _ResultColumn(title: 'Futures', result: item.futuresResult, isOptions: false)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortTime(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.length > 16 ? raw.substring(0, 16) : raw;
    }
  }

  Widget _verdictBadge(String verdict) {
    final color = verdict == 'WIN'
        ? AppColors.profit
        : verdict == 'FAIL'
            ? AppColors.loss
            : AppColors.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(verdict, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color)),
    );
  }
}

class _ResultColumn extends StatelessWidget {
  const _ResultColumn({required this.title, required this.result, required this.isOptions});
  final String title;
  final TradeResult result;
  final bool isOptions;

  Color get _color {
    if (result.isProfit) return AppColors.profit;
    if (result.isSlHit) return AppColors.loss;
    if (result.isOpen) return AppColors.warn;
    return AppColors.textMuted;
  }

  String get _pnlText {
    if (result.pnlValue == null) return result.label;
    if (isOptions) {
      final v = result.pnlValue!;
      return '${v >= 0 ? '+' : ''}₹${v.toStringAsFixed(0)}';
    }
    final pts = result.pnlValue!;
    return '${pts >= 0 ? '+' : ''}${pts.toStringAsFixed(1)} pts';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(result.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _color)),
          if (result.outcome == 'profit' || result.outcome == 'sl_hit')
            Text(
              result.outcome == 'profit' ? 'WIN' : 'FAIL',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _color),
            ),
          if (result.pnlValue != null) ...[
            const SizedBox(height: 2),
            Text(_pnlText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _color)),
            if (result.pnlPct != null)
              Text('${result.pnlPct! >= 0 ? '+' : ''}${result.pnlPct!.toStringAsFixed(1)}%', style: TextStyle(fontSize: 10, color: _color)),
          ],
        ],
      ),
    );
  }
}

class _SignalsEmptyState extends StatelessWidget {
  const _SignalsEmptyState({
    required this.health,
    required this.onRetry,
    required this.regimes,
  });

  final AsyncValue<dynamic> health;
  final AsyncValue<Map<String, dynamic>> regimes;
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
              offline ? 'Cannot load signals' : 'No CAN TAKE signal right now',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            regimes.when(
              data: (data) {
                final items = data['regimes'] as Map<String, dynamic>? ?? {};
                if (items.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: items.entries.map((e) {
                      final reg = e.value as Map<String, dynamic>? ?? {};
                      final label = reg['regime'] as String? ?? '—';
                      final adx = reg['adx'];
                      return Text(
                        '${e.key}: ${label.toUpperCase()}${adx != null ? ' (ADX $adx)' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: label == 'ranging' ? AppColors.warn : AppColors.textMuted,
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
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

class _AlphaSignalCard extends StatelessWidget {
  const _AlphaSignalCard({required this.signal});

  final Map<String, dynamic> signal;

  Color get _tierColor => switch (signal['tier']?.toString()) {
        'A+' => AppColors.profit,
        'A' => AppColors.accent,
        _ => AppColors.warn,
      };

  @override
  Widget build(BuildContext context) {
    final formatted = signal['formatted']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _tierColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _tierColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${signal['tier']} · ${signal['confluence_score']}/100',
                    style: TextStyle(color: _tierColor, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${signal['instrument']} ${signal['strategy']}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              signal['entry_zone']?.toString() ?? '',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              'Risk ₹${signal['risk_inr']} · ${signal['lots']} lot(s) · SL: ${signal['sl_rule']}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            if (formatted != null && formatted.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: AppColors.surface,
                    builder: (_) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.75,
                      builder: (_, controller) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: ListView(
                          controller: controller,
                          children: [
                            const Text('Alpha Signal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 12),
                            SelectableText(formatted, style: const TextStyle(fontSize: 12, height: 1.4)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.article_outlined, size: 16),
                label: const Text('Full signal card'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
