import 'package:flutter/material.dart';

import '../config.dart';
import '../models/market_session.dart';
import '../theme/app_theme.dart';

/// User-friendly error instead of raw Dio/WS stack traces.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.compact = false,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final bool compact;

  static String friendlyMessage(Object error) {
    final text = error.toString();
    if (text.contains('Operation not permitted') || text.contains('Connection failed')) {
      return 'Cannot reach the server. Check mobile data/Wi‑Fi and reinstall the latest APK.';
    }
    if (text.contains('Connection refused') || text.contains('Failed host lookup')) {
      return 'Server unreachable at ${AppConfig.apiBaseUrl}. Backend may be down.';
    }
    if (text.contains('timeout') || text.contains('Timeout')) {
      return 'Request timed out. Try again in a few seconds.';
    }
    return 'Something went wrong. Pull to refresh or tap Retry.';
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GlassErrorCard(title: title, message: message, onRetry: onRetry);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.loss.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.loss.withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.cloud_off_rounded, color: AppColors.loss, size: 40),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              AppConfig.apiBaseUrl,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.accent.withValues(alpha: 0.8), fontSize: 11),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry connection'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class GlassErrorCard extends StatelessWidget {
  const GlassErrorCard({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.loss.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.loss.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.loss, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (message != null)
                  Text(message!, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          if (onRetry != null)
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.accent, size: 20),
            ),
        ],
      ),
    );
  }
}

class DashboardStat extends StatelessWidget {
  const DashboardStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class MarketDashboard extends StatelessWidget {
  const MarketDashboard({
    super.key,
    required this.serverOk,
    required this.smartApiOk,
    required this.paperMode,
    this.session,
    this.brief,
    this.onRetry,
  });

  final bool serverOk;
  final bool smartApiOk;
  final bool paperMode;
  final MarketSessionInfo? session;
  final TraderBrief? brief;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Market pulse', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (onRetry != null)
                IconButton(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.accent),
                  tooltip: 'Refresh',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              DashboardStat(
                label: 'Server',
                value: serverOk ? 'Online' : 'Offline',
                icon: Icons.dns_rounded,
                color: serverOk ? AppColors.profit : AppColors.loss,
              ),
              const SizedBox(width: 8),
              DashboardStat(
                label: 'Broker feed',
                value: smartApiOk ? 'Connected' : 'Waiting',
                icon: Icons.hub_rounded,
                color: smartApiOk ? AppColors.profit : AppColors.warn,
              ),
              const SizedBox(width: 8),
              DashboardStat(
                label: 'Mode',
                value: paperMode ? 'Paper' : 'Live',
                icon: Icons.shield_outlined,
                color: paperMode ? AppColors.warn : AppColors.accent,
              ),
            ],
          ),
          if (session != null && session!.istTime.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        session!.signalsActive ? Icons.schedule_rounded : Icons.nightlight_round,
                        size: 18,
                        color: session!.signalsActive ? AppColors.profit : AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${session!.istTime} · ${session!.phaseLabel}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (session!.signalsActive && session!.minutesToNextBar != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Next 5m signal scan in ${session!.minutesToNextBar} min (${session!.nextBarAt})',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                  if (session!.fiiDii != null && session!.fiiDii!.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(session!.fiiDii!.summary, style: const TextStyle(fontSize: 11, color: AppColors.accent)),
                  ],
                ],
              ),
            ),
          ],
          if (brief != null && brief!.headline.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(brief!.headline, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
          if (brief != null && brief!.painPoints.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...brief!.painPoints.take(2).map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('⚠ ', style: TextStyle(fontSize: 11)),
                        Expanded(child: Text(p, style: const TextStyle(fontSize: 11, height: 1.3))),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
        ),
      ),
    );
  }
}
