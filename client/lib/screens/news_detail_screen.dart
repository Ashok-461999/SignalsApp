import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/news_intel.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

class NewsDetailScreen extends StatelessWidget {
  const NewsDetailScreen({super.key, required this.headline});

  final NewsHeadline headline;

  Color get _sentimentColor => switch (headline.sentiment) {
        'bullish' => AppColors.profit,
        'bearish' => AppColors.loss,
        _ => AppColors.warn,
      };

  Future<void> _openSource() async {
    final uri = Uri.tryParse(headline.url);
    if (uri == null || headline.url.isEmpty) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final regionColor = headline.isGlobal ? AppColors.warn : AppColors.accent;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('News reader'),
        actions: [
          if (headline.url.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open original',
              onPressed: _openSource,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _tag(headline.isGlobal ? 'GLOBAL' : 'INDIA', regionColor),
              const SizedBox(width: 8),
              _tag(headline.sentiment.toUpperCase(), _sentimentColor),
              const Spacer(),
              if (headline.timeLabel.isNotEmpty)
                Text(headline.timeLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Text(headline.source, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          if (headline.fullTimeLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    headline.fullTimeLabel,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            headline.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.35),
          ),
          const SizedBox(height: 16),
          AlphaSurface(
            accent: AppColors.accent,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.show_chart_rounded, size: 16, color: AppColors.accent),
                    SizedBox(width: 6),
                    Text('Markets that may be affected', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: headline.affectedMarkets
                      .map((m) => Chip(
                            label: Text(m, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                            side: BorderSide(color: AppColors.accent.withValues(alpha: 0.35)),
                          ))
                      .toList(),
                ),
                if (headline.affectedMarkets.isEmpty)
                  const Text('Broad market — may affect NIFTY & BANKNIFTY', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (headline.prediction.isNotEmpty) ...[
            const SizedBox(height: 12),
            AlphaSurface(
              accent: _sentimentColor,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trade impact · ${headline.score}% confidence',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _sentimentColor),
                  ),
                  const SizedBox(height: 8),
                  Text(headline.prediction, style: const TextStyle(fontSize: 14, height: 1.45)),
                ],
              ),
            ),
          ],
          if (headline.summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(headline.summary, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textPrimary)),
          ] else if (headline.prediction.isEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Tap below to read the full article on the source website.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
            ),
          ],
          if (headline.url.isNotEmpty) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openSource,
              icon: const Icon(Icons.article_outlined),
              label: Text('Read on ${headline.source}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );
}
