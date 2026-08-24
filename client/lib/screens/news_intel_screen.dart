import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_session.dart';
import '../models/news_intel.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/status_widgets.dart';

enum _NewsFilter { all, india, global }

class NewsIntelScreen extends ConsumerStatefulWidget {
  const NewsIntelScreen({super.key});

  @override
  ConsumerState<NewsIntelScreen> createState() => _NewsIntelScreenState();
}

class _NewsIntelScreenState extends ConsumerState<NewsIntelScreen> {
  _NewsFilter _filter = _NewsFilter.all;
  bool _showAnalysis = false;

  List<NewsHeadline> _filtered(List<NewsHeadline> items) => switch (_filter) {
        _NewsFilter.india => items.where((h) => h.isIndian).toList(),
        _NewsFilter.global => items.where((h) => h.isGlobal).toList(),
        _ => items,
      };

  @override
  Widget build(BuildContext context) {
    final intel = ref.watch(marketIntelProvider);

    return intel.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 12),
            Text('Loading live news…', style: TextStyle(color: AppColors.textMuted)),
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
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _TraderBriefCard(brief: data.traderBrief, session: data.marketSession),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Live news',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: () => ref.invalidate(marketIntelProvider),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Indian & global markets — Moneycontrol, ET, Reuters & more',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _filter == _NewsFilter.all,
                      onTap: () => setState(() => _filter = _NewsFilter.all),
                    ),
                    _FilterChip(
                      label: 'India',
                      selected: _filter == _NewsFilter.india,
                      onTap: () => setState(() => _filter = _NewsFilter.india),
                    ),
                    _FilterChip(
                      label: 'Global',
                      selected: _filter == _NewsFilter.global,
                      onTap: () => setState(() => _filter = _NewsFilter.global),
                    ),
                  ],
                ),
              ),
            ),
            if (data.headlines.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No headlines — pull to refresh', style: TextStyle(color: AppColors.textMuted))),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final headlines = _filtered(data.headlines);
                    if (index >= headlines.length) return null;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(16, index == 0 ? 0 : 0, 16, 8),
                      child: _NewsFeedCard(h: headlines[index]),
                    );
                  },
                  childCount: _filtered(data.headlines).length,
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _showAnalysis = !_showAnalysis),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'GIFT Nifty & trade analysis',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(_showAnalysis ? Icons.expand_less : Icons.expand_more, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_showAnalysis) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _GiftNiftyCard(gift: data.giftNifty),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _MarketBiasSummary(predictions: data.predictions),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _PredictionCard(p: data.predictions[index]),
                  ),
                  childCount: data.predictions.length,
                ),
              ),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
    );
  }
}

class _TraderBriefCard extends StatelessWidget {
  const _TraderBriefCard({required this.brief, required this.session});
  final TraderBrief brief;
  final MarketSessionInfo session;

  @override
  Widget build(BuildContext context) {
    final headline = brief.headline.isNotEmpty ? brief.headline : session.phaseLabel;
    if (headline.isEmpty) return const SizedBox.shrink();

    return AlphaSurface(
      accent: AppColors.accent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          if (brief.actionItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...brief.actionItems.take(3).map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('→ ', style: TextStyle(color: AppColors.accent, fontSize: 12)),
                        Expanded(child: Text(a, style: const TextStyle(fontSize: 12, height: 1.3))),
                      ],
                    ),
                  ),
                ),
          ],
          if (brief.painPoints.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              brief.painPoints.first,
              style: const TextStyle(fontSize: 11, color: AppColors.warn, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? AppColors.accent : AppColors.textMuted,
      ),
      selectedColor: AppColors.accent.withValues(alpha: 0.18),
      backgroundColor: AppColors.surfaceHigh.withValues(alpha: 0.5),
      side: BorderSide(color: selected ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border),
    );
  }
}

class _NewsFeedCard extends StatelessWidget {
  const _NewsFeedCard({required this.h});
  final NewsHeadline h;

  @override
  Widget build(BuildContext context) {
    final accent = switch (h.sentiment) {
      'bullish' => AppColors.profit,
      'bearish' => AppColors.loss,
      _ => AppColors.textMuted,
    };
    final regionColor = h.isGlobal ? AppColors.warn : AppColors.accent;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tag(h.isGlobal ? 'GLOBAL' : 'INDIA', regionColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  h.source,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _tag(h.sentiment.toUpperCase(), accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            h.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
          ),
          if (h.prediction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              h.prediction,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (h.symbols.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: h.symbols
                  .take(4)
                  .map((s) => Chip(
                        label: Text(s, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
      );
}

class _GiftNiftyCard extends StatelessWidget {
  const _GiftNiftyCard({required this.gift});
  final GiftNiftyInsight gift;

  @override
  Widget build(BuildContext context) {
    if (!gift.available) {
      return AlphaSurface(
        accent: AppColors.warn,
        padding: const EdgeInsets.all(14),
        child: Text(
          gift.summary.isNotEmpty ? gift.summary : 'GIFT Nifty data unavailable',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }

    final negative = gift.sessionClose == 'negative';
    final positive = gift.sessionClose == 'positive';
    final accent = negative ? AppColors.loss : positive ? AppColors.profit : AppColors.warn;

    return AlphaSurface(
      accent: accent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GIFT Nifty → Nifty open', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (gift.lastPrice != null)
            Text(
              '${gift.lastPrice!.toStringAsFixed(1)} (${gift.changePct != null ? '${gift.changePct! >= 0 ? '+' : ''}${gift.changePct!.toStringAsFixed(2)}%' : ''})',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accent),
            ),
          const SizedBox(height: 6),
          Text(gift.summary, style: const TextStyle(fontSize: 12, height: 1.35)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _probTile('Gap DOWN', '${gift.negativeOpenProbability}%', AppColors.loss)),
              const SizedBox(width: 8),
              Expanded(child: _probTile('Gap UP', '${gift.positiveOpenProbability}%', AppColors.profit)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _probTile(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bg.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      );
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
    return AlphaSurface(
      accent: _accent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(p.symbol, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p.name,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _chip(p.outlook.toUpperCase(), _accent),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${p.confidence}% · ${p.headlineCount} headline(s)',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          if (p.moveLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.moveLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _accent)),
          ],
          if (p.moveReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.moveReason, style: const TextStyle(fontSize: 12, height: 1.35), maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
      );
}

class _MarketBiasSummary extends StatelessWidget {
  const _MarketBiasSummary({required this.predictions});
  final List<SymbolPrediction> predictions;

  @override
  Widget build(BuildContext context) {
    final indices = predictions.where((p) => p.type == 'index').take(4).toList();
    if (indices.isEmpty) return const SizedBox.shrink();

    final bullish = indices.where((p) => p.outlook == 'bullish').map((p) => p.symbol).join(', ');
    final bearish = indices.where((p) => p.outlook == 'bearish').map((p) => p.symbol).join(', ');

    return AlphaSurface(
      accent: AppColors.accent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Index bias', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          if (bullish.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Bullish: $bullish', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (bearish.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Bearish: $bearish', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
