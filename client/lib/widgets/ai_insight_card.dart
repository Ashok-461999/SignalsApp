import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class AiInsightCard extends ConsumerWidget {
  const AiInsightCard({super.key, required this.signal});

  final SignalModel signal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiEnabled = ref.watch(aiAnalysisEnabledProvider);
    if (!aiEnabled) return const SizedBox.shrink();

    final insight = ref.watch(signalAiInsightProvider(signal));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A2332),
            AppColors.surfaceHigh,
          ],
        ),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Claude AI · News + setup',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              insight.when(
                data: (_) => IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () => ref.invalidate(signalAiInsightProvider(signal)),
                ),
                loading: () => const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                ),
                error: (_, __) => IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () => ref.invalidate(signalAiInsightProvider(signal)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          insight.when(
            data: (text) => SelectableText(text, style: const TextStyle(fontSize: 13, height: 1.45)),
            loading: () => const Text('Reading headlines & analyzing…', style: TextStyle(color: AppColors.textMuted)),
            error: (e, _) => Text(
              'AI unavailable: $e',
              style: const TextStyle(color: AppColors.loss, fontSize: 12),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Second opinion only — not financial advice.',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
