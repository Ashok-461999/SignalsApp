import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import 'setup_detail_screen.dart';

class SignalsScreen extends ConsumerWidget {
  const SignalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signals = ref.watch(activeSignalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Signals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showGuide(context),
          ),
        ],
      ),
      body: signals.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Waiting for market scan…\nNo setup evaluated yet.',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final takeCount = list.where((s) => s.tradeDecision == 'TAKE').length;
          final sorted = [...list]..sort((a, b) {
              const order = {'TAKE': 0, 'NO_TRADE': 1, 'SIT_OUT': 2};
              return (order[a.tradeDecision] ?? 9).compareTo(order[b.tradeDecision] ?? 9);
            });

          return Column(
            children: [
              _SummaryBanner(takeCount: takeCount, total: list.length),
              Expanded(
                child: ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (_, i) => _SignalTile(signal: sorted[i]),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('WS error: $e')),
      ),
    );
  }

  void _showGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Strategy guide'),
        content: const SingleChildScrollView(
          child: Text(
            'TAKE — trade in your broker app\n'
            'NO_TRADE — setup fired but skip (wrong regime, poor R:R, high IV)\n'
            'SIT_OUT — ranging day, theta wins — no directional buys\n\n'
            'Trending → ORB, EMA pullback, VWAP trend\n'
            'Ranging → spreads or sit out\n'
            'Volatile → breakout only, size down',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.takeCount, required this.total});
  final int takeCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final msg = takeCount > 0
        ? '$takeCount TAKE signal(s) — trade these'
        : 'No TAKE signals — sit out or wait';
    return Material(
      color: takeCount > 0 ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              takeCount > 0 ? Icons.check_circle : Icons.pause_circle_outline,
              color: takeCount > 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('$total eval', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.signal});
  final SignalModel signal;

  @override
  Widget build(BuildContext context) {
    final decision = signal.tradeDecision;
    final chipColor = switch (decision) {
      'TAKE' => Colors.green.shade100,
      'SIT_OUT' => Colors.grey.shade300,
      _ => Colors.orange.shade100,
    };
    final chipTextColor = switch (decision) {
      'TAKE' => Colors.green.shade900,
      'SIT_OUT' => Colors.grey.shade800,
      _ => Colors.orange.shade900,
    };

    final title = signal.setupName == 'regime_advisory'
        ? '${signal.instrument} · regime'
        : '${signal.setupName} · ${signal.instrument}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        isThreeLine: true,
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (signal.regime.isNotEmpty)
              Text('Regime: ${signal.regime}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            if (signal.direction != 'neutral')
              Text('${signal.direction.toUpperCase()} · R:R ${signal.riskReward.toStringAsFixed(1)}'),
            if (signal.decisionReason.isNotEmpty)
              Text(
                signal.decisionReason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        trailing: Chip(
          label: Text(decision, style: TextStyle(color: chipTextColor, fontWeight: FontWeight.bold)),
          backgroundColor: chipColor,
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SetupDetailScreen(signal: signal)),
        ),
      ),
    );
  }
}
