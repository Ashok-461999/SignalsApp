import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/news_intel.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/status_widgets.dart';

class NewsIntelScreen extends ConsumerWidget {
  const NewsIntelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intel = ref.watch(marketIntelProvider);

    return intel.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 12),
            Text('Fetching live news…', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
      error: (e, _) => AppErrorView(
        title: 'News unavailable',
        message: AppErrorView.friendlyMessage(e),
        onRetry: () => ref.invalidate(marketIntelProvider),
      ),
      data: (data) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(marketIntelProvider);
          await ref.read(marketIntelProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Row(
              children: [
                const Text('Market intel', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => ref.invalidate(marketIntelProvider),
                ),
              ],
            ),
            if (data.disclaimer.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(data.disclaimer, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            const Text('Index move targets (~100 pts)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Advanced models: ORB, EMA, VWAP, range + news momentum',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            ...data.predictions.map((p) => _PredictionCard(p: p)),
            const SizedBox(height: 16),
            const Text('Live headlines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (data.headlines.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No headlines right now', style: TextStyle(color: AppColors.textMuted))),
              )
            else
              ...data.headlines.map((h) => _HeadlineCard(h: h)),
          ],
        ),
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.p});
  final SymbolPrediction p;

  Color get _accent => switch (p.outlook) {
        'bullish' => AppColors.profit,
        'bearish' => AppColors.loss,
        _ => AppColors.warn,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AlphaSurface(
        accent: _accent,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  p.symbol,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Text(p.name, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const Spacer(),
                _chip(p.outlook.toUpperCase(), _accent),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${p.confidence}% confidence · ${p.headlineCount} headline(s)',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            if (p.movePoints != null && p.movePoints! > 0) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bg.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _accent.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.moveLabel,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _accent),
                    ),
                    if (p.spotPrice != null && p.targetPrice != null)
                      Text(
                        '${p.spotPrice!.toStringAsFixed(1)} → ${p.targetPrice!.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    if (p.strategy.isNotEmpty)
                      Text('Strategy: ${p.strategy}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            if (p.models.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: p.models.map((m) => Chip(label: Text(m, style: const TextStyle(fontSize: 10)))).toList(),
              ),
            ],
            const SizedBox(height: 6),
            Text(p.optionHint, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(p.prediction, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.h});
  final NewsHeadline h;

  @override
  Widget build(BuildContext context) {
    final accent = switch (h.sentiment) {
      'bullish' => AppColors.profit,
      'bearish' => AppColors.loss,
      _ => AppColors.textMuted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(h.source, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                const Spacer(),
                Text(h.sentiment.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent)),
              ],
            ),
            const SizedBox(height: 6),
            Text(h.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (h.symbols.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: h.symbols.map((s) => Chip(label: Text(s, style: const TextStyle(fontSize: 10)))).toList(),
              ),
            ],
            if (h.prediction.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(h.prediction, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}
