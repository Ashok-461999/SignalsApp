import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_mode.dart';
import '../providers/app_providers.dart';
import '../theme/app_branding.dart';
import '../theme/app_theme.dart';

/// Top bar: branding + Indian Market vs Crypto toggle.
class MarketModeSwitcher extends ConsumerWidget {
  const MarketModeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(marketModeProvider);
    final topPad = MediaQuery.paddingOf(context).top;

    return Material(
      color: AppColors.surface.withValues(alpha: 0.98),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.98),
          border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
                  ),
                  child: const Icon(Icons.auto_graph_rounded, color: AppColors.accent, size: 22),
                ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppBranding.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                        ),
                        Text(
                          AppBranding.tagline,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (mode == MarketMode.crypto)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warn.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warn.withValues(alpha: 0.5)),
                      ),
                      child: const Text(
                        'BETA',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.warn),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<MarketMode>(
                segments: const [
                  ButtonSegment(
                    value: MarketMode.indian,
                    label: Text('Indian Market'),
                    icon: Icon(Icons.show_chart_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: MarketMode.crypto,
                    label: Text('Crypto'),
                    icon: Icon(Icons.currency_bitcoin_rounded, size: 18),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selected) {
                  ref.read(marketModeProvider.notifier).setMode(selected.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.accent.withValues(alpha: 0.22);
                    }
                    return AppColors.surfaceHigh.withValues(alpha: 0.75);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return AppColors.accent;
                    return AppColors.textMuted;
                  }),
                  side: WidgetStateProperty.all(BorderSide(color: AppColors.border.withValues(alpha: 0.8))),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

/// Shown on tabs when crypto backend is not wired yet.
class CryptoComingSoon extends StatelessWidget {
  const CryptoComingSoon({
    super.key,
    required this.title,
    this.subtitle = 'Crypto signals, charts & P&L are coming in the next update.',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rocket_launch_rounded, size: 56, color: AppColors.accent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: AppColors.textMuted), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: cryptoWatchlist
                  .map((c) => Chip(
                        avatar: const Icon(Icons.circle, size: 8, color: AppColors.accent),
                        label: Text('${c.symbol}/${c.quote}'),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
