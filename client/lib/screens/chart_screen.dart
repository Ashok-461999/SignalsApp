import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/candle.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/candlestick_chart.dart';

class ChartScreen extends ConsumerStatefulWidget {
  const ChartScreen({super.key, required this.instrument, this.interval = '5m'});
  final String instrument;
  final String interval;

  @override
  ConsumerState<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends ConsumerState<ChartScreen> {
  late String _interval;

  @override
  void initState() {
    super.initState();
    _interval = widget.interval;
  }

  @override
  Widget build(BuildContext context) {
    final candles = ref.watch(candlesProvider((widget.instrument, _interval)));
    final prices = ref.watch(livePricesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.instrument),
            prices.when(
              data: (p) {
                final live = p[widget.instrument];
                return Text(
                  live != null ? live.toStringAsFixed(2) : 'Live —',
                  style: const TextStyle(fontSize: 13, color: AppColors.accent),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(candlesProvider((widget.instrument, _interval))),
          ),
        ],
      ),
      body: candles.when(
        data: (data) {
          final list = data.candles;
          final last = list.isNotEmpty ? list.last : null;
          final change = list.length >= 2 ? list.last.close - list[list.length - 2].close : 0.0;
          final changePct = list.length >= 2 && list[list.length - 2].close != 0
              ? change / list[list.length - 2].close * 100
              : 0.0;
          final up = change >= 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: ['1m', '5m', '15m'].map((iv) {
                  final selected = _interval == iv;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(iv),
                      selected: selected,
                      onSelected: (_) => setState(() => _interval = iv),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              if (last != null)
                Row(
                  children: [
                    Text(
                      last.close.toStringAsFixed(2),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (up ? AppColors.profit : AppColors.loss).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${up ? '+' : ''}${change.toStringAsFixed(1)} (${changePct.toStringAsFixed(2)}%)',
                        style: TextStyle(
                          color: up ? AppColors.profit : AppColors.loss,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                'O ${last?.open.toStringAsFixed(1) ?? '—'}  H ${last?.high.toStringAsFixed(1) ?? '—'}  '
                'L ${last?.low.toStringAsFixed(1) ?? '—'}  V ${last != null ? (last.volume / 1000).toStringAsFixed(1) + 'k' : '—'}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              CandlestickChart(candles: list, height: 320, showVolume: true),
              const SizedBox(height: 16),
              _OhlcGrid(candles: list),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppColors.loss))),
      ),
    );
  }
}

class _OhlcGrid extends StatelessWidget {
  const _OhlcGrid({required this.candles});
  final List<Candle> candles;

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) return const SizedBox.shrink();
    final recent = candles.length > 6 ? candles.sublist(candles.length - 6) : candles;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recent bars', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...recent.reversed.map((c) {
              final bull = c.close >= c.open;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      bull ? Icons.north_east_rounded : Icons.south_east_rounded,
                      size: 14,
                      color: bull ? AppColors.profit : AppColors.loss,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${c.timestamp.hour.toString().padLeft(2, '0')}:${c.timestamp.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                    Text('${c.close.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
