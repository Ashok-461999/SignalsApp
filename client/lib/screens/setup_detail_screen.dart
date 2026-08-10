import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';

class SetupDetailScreen extends ConsumerStatefulWidget {
  const SetupDetailScreen({super.key, required this.signal});
  final SignalModel signal;

  @override
  ConsumerState<SetupDetailScreen> createState() => _SetupDetailScreenState();
}

class _SetupDetailScreenState extends ConsumerState<SetupDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.signal;
    final candles = ref.watch(candlesProvider((s.instrument, '5m')));

    return Scaffold(
      appBar: AppBar(
        title: Text(s.setupName),
        backgroundColor: _decisionColor(s.tradeDecision),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DecisionBanner(signal: s),
          const SizedBox(height: 12),
          Text('${s.instrument} · ${s.direction.toUpperCase()}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _row('Entry (underlying)', s.underlyingEntry.toStringAsFixed(1)),
          _row('Stop loss', s.underlyingStopLoss.toStringAsFixed(1)),
          _row('Target T1', s.underlyingTarget.isNotEmpty ? s.underlyingTarget[0].toStringAsFixed(1) : '—'),
          _row('Strike', s.suggestedStrike.toStringAsFixed(0)),
          _row('Expiry', s.suggestedExpiry),
          _row('IV percentile', '${s.ivPercentile.toStringAsFixed(0)}%'),
          _row('R:R', s.riskReward.toStringAsFixed(2)),
          _row('Size', '${s.positionSize} lots'),
          _row('Premium @ stop (info)', s.premiumStopReference.toStringAsFixed(1)),
          const Divider(),
          Text('Backtest stats', style: Theme.of(context).textTheme.titleMedium),
          _row('Win rate', '${s.backtestStats['win_rate'] ?? '—'}%'),
          _row('Expectancy', '${s.backtestStats['expectancy'] ?? '—'}'),
          _row('Max DD', '${s.backtestStats['max_drawdown'] ?? '—'}'),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: candles.when(
              data: (data) {
                final c = data.candles;
                if (c.isEmpty) return const Center(child: Text('No chart data'));
                final spots = <FlSpot>[];
                for (var i = 0; i < c.length; i++) {
                  spots.add(FlSpot(i.toDouble(), c[i].close));
                }
                return LineChart(LineChartData(
                  lineBarsData: [
                    LineChartBarData(spots: spots, dotData: const FlDotData(show: false)),
                  ],
                ));
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('$e'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: s.tradeDecision == 'TAKE'
                      ? () async {
                          await ref.read(apiServiceProvider).approveSignal(s);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Approved — journal entry created')),
                            );
                          }
                        }
                      : null,
                  child: const Text('Approve (TAKE only)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await ref.read(apiServiceProvider).rejectSignal(s);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Rejected — recorded in journal')),
                      );
                    }
                  },
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))],
        ),
      );
}

Color? _decisionColor(String decision) => switch (decision) {
      'TAKE' => Colors.green.shade700,
      'SIT_OUT' => Colors.grey.shade600,
      _ => Colors.orange.shade700,
    };

class _DecisionBanner extends StatelessWidget {
  const _DecisionBanner({required this.signal});
  final SignalModel signal;

  @override
  Widget build(BuildContext context) {
    final d = signal.tradeDecision;
    final bg = switch (d) {
      'TAKE' => Colors.green.shade50,
      'SIT_OUT' => Colors.grey.shade200,
      _ => Colors.orange.shade50,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          if (signal.regime.isNotEmpty) Text('Regime: ${signal.regime} · ${signal.strategyFit}'),
          if (signal.decisionReason.isNotEmpty) Text(signal.decisionReason),
        ],
      ),
    );
  }
}
