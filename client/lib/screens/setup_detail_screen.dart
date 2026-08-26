import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../screens/chart_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_insight_card.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/status_widgets.dart';

class SetupDetailScreen extends ConsumerStatefulWidget {
  const SetupDetailScreen({super.key, required this.signal});
  final SignalModel signal;

  @override
  ConsumerState<SetupDetailScreen> createState() => _SetupDetailScreenState();
}

class _SetupDetailScreenState extends ConsumerState<SetupDetailScreen> {
  String _interval = '5m';

  @override
  Widget build(BuildContext context) {
    final s = widget.signal;
    final candles = ref.watch(candlesProvider((s.instrument, _interval)));

    return Scaffold(
      appBar: AppBar(
        title: Text(s.setupName.replaceAll('_', ' ').toUpperCase()),
        actions: [
          IconButton(
            icon: const Icon(Icons.candlestick_chart_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChartScreen(instrument: s.instrument, interval: _interval)),
            ),
          ),
        ],
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _DecisionHero(signal: s),
          if (s.brokerOrderHint.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.take,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.takeBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('OPTIONS · PRIMARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.profit)),
                  const SizedBox(height: 4),
                  const Text('Place in broker', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Text(s.brokerOrderHint, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.profit)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: s.brokerOrderHint));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Options order copied')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy options order'),
                  ),
                  if (s.entryPremiumEstimate > 0)
                    Text(
                      'Est. premium ~₹${s.entryPremiumEstimate.toStringAsFixed(0)} per unit · IV ${s.ivPercentile.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  if (s.maxLossInr > 0)
                    Text(
                      'Max loss ~₹${s.maxLossInr.toStringAsFixed(0)} · need ~₹${s.premiumRequiredInr.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
          ],
          if (s.hasFuturesLeg) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('FUTURES · BACKUP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accent)),
                  const SizedBox(height: 4),
                  Text(
                    s.dualLegNote.isNotEmpty ? s.dualLegNote : 'If option SL hits but index keeps moving',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.futuresCanTake
                        ? '${s.futuresActionLabel} × ${s.futuresLots} lots'
                        : s.futuresActionLabel,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  if (s.futuresCanTake && s.futuresBrokerHint.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: s.futuresBrokerHint));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Futures order copied')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy futures order'),
                    ),
                  ],
                  if (s.futuresCanTake && s.futuresMaxLossInr > 0)
                    Text(
                      'Max loss ~₹${s.futuresMaxLossInr.toStringAsFixed(0)} · margin ~₹${s.futuresMarginInr.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    )
                  else if (s.futuresReason.isNotEmpty)
                    Text(s.futuresReason, style: const TextStyle(fontSize: 12, color: AppColors.warn)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          AiInsightCard(signal: s),
          const SizedBox(height: 16),
          Row(
            children: ['1m', '5m', '15m'].map((iv) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(iv),
                  selected: _interval == iv,
                  onSelected: (_) => setState(() => _interval = iv),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          candles.when(
            data: (data) => CandlestickChart(
              candles: data.candles,
              height: 260,
              entry: s.underlyingEntry,
              stop: s.underlyingStopLoss,
              target: s.underlyingTarget.isNotEmpty ? s.underlyingTarget.first : null,
            ),
            loading: () => const SizedBox(height: 260, child: Center(child: CircularProgressIndicator(color: AppColors.accent))),
            error: (e, _) => AppErrorView(
              title: 'Chart unavailable',
              message: AppErrorView.friendlyMessage(e),
              compact: true,
              onRetry: () => ref.invalidate(candlesProvider((s.instrument, _interval))),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Options trade (primary)', icon: Icons.receipt_long_rounded),
          _MetricGrid(children: [
            _MetricTile(label: 'Strike', value: s.optionLabel.isNotEmpty ? s.optionLabel : s.suggestedStrike.toStringAsFixed(0), icon: Icons.tag_rounded),
            _MetricTile(label: 'Expiry', value: s.expiryLabel.isNotEmpty ? s.expiryLabel : s.suggestedExpiry, icon: Icons.event_rounded),
            _MetricTile(label: 'Est. premium', value: s.entryPremiumEstimate > 0 ? '₹${s.entryPremiumEstimate.toStringAsFixed(0)}' : '—', icon: Icons.payments_rounded),
            _MetricTile(label: 'Lots', value: '${s.positionSize}', icon: Icons.pie_chart_rounded),
            _MetricTile(label: 'IV %ile', value: '${s.ivPercentile.toStringAsFixed(0)}%', icon: Icons.waves_rounded),
            _MetricTile(label: 'Prem @ SL', value: s.premiumStopReference.toStringAsFixed(1), icon: Icons.warning_amber_rounded),
            _MetricTile(label: 'Max loss', value: s.maxLossInr > 0 ? '₹${s.maxLossInr.toStringAsFixed(0)}' : '—', icon: Icons.warning_amber_rounded),
          ]),
          const SizedBox(height: 16),
          _SectionTitle('Futures trade (backup)', icon: Icons.show_chart_rounded),
          _MetricGrid(children: [
            _MetricTile(label: 'Action', value: s.futuresActionLabel.isNotEmpty ? s.futuresActionLabel : '—', icon: Icons.swap_horiz_rounded),
            _MetricTile(label: 'Lots', value: s.futuresLots > 0 ? '${s.futuresLots}' : '—', icon: Icons.pie_chart_rounded),
            _MetricTile(label: 'Max loss', value: s.futuresMaxLossInr > 0 ? '₹${s.futuresMaxLossInr.toStringAsFixed(0)}' : '—', icon: Icons.warning_amber_rounded),
            _MetricTile(label: 'Margin est.', value: s.futuresMarginInr > 0 ? '₹${s.futuresMarginInr.toStringAsFixed(0)}' : '—', icon: Icons.account_balance_wallet_rounded),
            _MetricTile(label: 'Margin/lot', value: s.futuresMarginPerLotInr > 0 ? '₹${s.futuresMarginPerLotInr.toStringAsFixed(0)}' : '—', icon: Icons.payments_rounded),
            _MetricTile(label: 'Affordable', value: s.futuresCanTake ? 'Yes' : 'No', icon: Icons.check_circle_outline_rounded, valueColor: s.futuresCanTake ? AppColors.profit : AppColors.warn),
          ]),
          const SizedBox(height: 16),
          _SectionTitle('Underlying plan', icon: Icons.route_rounded),
          _MetricGrid(children: [
            _MetricTile(label: 'Instrument', value: s.instrument, icon: Icons.layers_rounded),
            _MetricTile(label: 'Direction', value: s.direction.toUpperCase(), icon: Icons.swap_vert_rounded),
            _MetricTile(label: 'Entry', value: s.underlyingEntry.toStringAsFixed(1), icon: Icons.login_rounded),
            _MetricTile(label: 'Stop', value: s.underlyingStopLoss.toStringAsFixed(1), icon: Icons.shield_rounded, valueColor: AppColors.loss),
            _MetricTile(
              label: 'Target',
              value: s.underlyingTarget.isNotEmpty ? s.underlyingTarget[0].toStringAsFixed(1) : '—',
              icon: Icons.flag_rounded,
              valueColor: AppColors.profit,
            ),
            _MetricTile(label: 'R:R', value: s.riskReward.toStringAsFixed(2), icon: Icons.balance_rounded),
          ]),
          const SizedBox(height: 16),
          _SectionTitle('Backtest (before you trade)', icon: Icons.science_rounded),
          _MetricGrid(children: [
            _MetricTile(
              label: 'Verdict',
              value: s.backtestVerdict == 'PROFITABLE' ? 'Profitable' : s.backtestVerdict == 'NOT_PROFITABLE' ? 'Not profitable' : s.backtestVerdict,
              icon: Icons.verified_rounded,
              valueColor: s.backtestOk ? AppColors.profit : s.backtestFailed ? AppColors.loss : AppColors.warn,
            ),
            _MetricTile(label: 'Win rate', value: s.backtestWinRate > 0 ? '${s.backtestWinRate.toStringAsFixed(0)}%' : '—', icon: Icons.percent_rounded),
            _MetricTile(label: 'Profit factor', value: s.backtestProfitFactor > 0 ? s.backtestProfitFactor.toStringAsFixed(2) : '—', icon: Icons.trending_up_rounded),
            _MetricTile(label: 'Expectancy', value: s.backtestExpectancy != 0 ? '${s.backtestExpectancy.toStringAsFixed(1)} pts' : '—', icon: Icons.show_chart_rounded),
            _MetricTile(label: 'Max DD', value: s.backtestMaxDrawdown > 0 ? s.backtestMaxDrawdown.toStringAsFixed(0) : '—', icon: Icons.trending_down_rounded),
            _MetricTile(label: 'Trades', value: s.backtestTradeCount > 0 ? '${s.backtestTradeCount}' : '—', icon: Icons.history_rounded),
          ]),
          if (s.backtestSummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.backtestSummary, style: TextStyle(fontSize: 12, color: s.backtestOk ? AppColors.profit : AppColors.warn)),
          ],
          const SizedBox(height: 16),
          _SectionTitle('Backtest registry', icon: Icons.history_rounded),
          _MetricGrid(children: [
            _MetricTile(label: 'Win rate', value: '${s.backtestStats['win_rate'] ?? '—'}%', icon: Icons.percent_rounded),
            _MetricTile(label: 'Expectancy', value: '${s.backtestStats['expectancy'] ?? '—'}', icon: Icons.trending_up_rounded),
            _MetricTile(label: 'Max DD', value: '${s.backtestStats['max_drawdown'] ?? '—'}', icon: Icons.trending_down_rounded),
          ]),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: s.tradeDecision == 'TAKE'
                      ? () async {
                          await ref.read(apiServiceProvider).approveSignal(s);
                          ref.invalidate(journalProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to journal')),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Take trade'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(apiServiceProvider).rejectSignal(s);
                    ref.invalidate(journalProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Skipped — logged')),
                      );
                    }
                  },
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Skip'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecisionHero extends StatelessWidget {
  const _DecisionHero({required this.signal});
  final SignalModel signal;

  @override
  Widget build(BuildContext context) {
    final d = signal.tradeDecision;
    final accent = decisionAccent(d);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: decisionSurface(d),
        border: Border.all(color: decisionBorder(d)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                d == 'TAKE' ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: accent,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(d, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: accent)),
            ],
          ),
          if (signal.regime.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${signal.regime} · ${signal.strategyFit}', style: const TextStyle(color: AppColors.textMuted)),
            ),
          if (signal.decisionReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(signal.decisionReason),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: children,
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: valueColor ?? AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
