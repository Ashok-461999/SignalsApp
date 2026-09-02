import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/status_widgets.dart';

/// Primary Options Alpha Engine screen — institutional signal cards.
class AlphaScreen extends ConsumerStatefulWidget {
  const AlphaScreen({super.key});

  @override
  ConsumerState<AlphaScreen> createState() => _AlphaScreenState();
}

class _AlphaScreenState extends ConsumerState<AlphaScreen> {
  bool _scanning = false;

  Future<void> _refresh() async {
    ref.invalidate(healthProvider);
    ref.invalidate(alphaSignalsProvider);
    ref.invalidate(alphaPrepProvider);
    ref.invalidate(alphaStatusProvider);
  }

  Future<void> _triggerScan() async {
    setState(() => _scanning = true);
    try {
      await ref.read(apiServiceProvider).triggerAlphaScan();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alpha scan complete')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: ${AppErrorView.friendlyMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(healthProvider);
    final signals = ref.watch(alphaSignalsProvider);
    final prep = ref.watch(alphaPrepProvider);
    final status = ref.watch(alphaStatusProvider);
    final server = AppConfig.apiBaseUrl;

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Options Alpha Engine',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SMC · OI · GEX · Greeks · Confluence ≥70',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 12),
                  _ConnectionBanner(health: health, server: server),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _scanning ? null : _triggerScan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.radar_rounded, size: 18),
                    label: Text(_scanning ? 'Scanning…' : 'Run scan'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          ),
          status.when(
            data: (s) {
              final count = s['signal_count_today'] ?? 0;
              if (count == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '$count signal(s) today · SL hits: ${s['sl_hits_today'] ?? 0}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
          health.when(
            data: (_) => signals.when(
              data: (data) {
                final list = (data['signals'] as List<dynamic>? ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                if (list.isEmpty) {
                  return SliverToBoxAdapter(child: _PrepSection(prep: prep));
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _AlphaSignalCard(signal: list[i]),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              ),
              error: (e, _) => SliverFillRemaining(
                child: _OfflineHelp(server: server, error: e, onRetry: _refresh),
              ),
            ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
            ),
            error: (e, _) => SliverFillRemaining(
              child: _OfflineHelp(server: server, error: e, onRetry: _refresh),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.health, required this.server});

  final AsyncValue<dynamic> health;
  final String server;

  @override
  Widget build(BuildContext context) {
    return health.when(
      data: (h) {
        final ok = h.status == 'ok';
        final smart = h.smartapi?['connected'] == true;
        final color = ok && smart ? AppColors.profit : AppColors.warn;
        return AlphaSurface(
          padding: const EdgeInsets.all(12),
          accent: color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(ok ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    ok && smart ? 'Backend online · SmartAPI connected' : 'Backend online · broker reconnecting',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(server, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        );
      },
      loading: () => AlphaSurface(
        padding: const EdgeInsets.all(12),
        accent: AppColors.accent,
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Connecting to $server…', style: const TextStyle(fontSize: 12))),
          ],
        ),
      ),
      error: (_, __) => AlphaSurface(
        padding: const EdgeInsets.all(12),
        accent: AppColors.loss,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: AppColors.loss, size: 18),
                SizedBox(width: 8),
                Text('Backend offline', style: TextStyle(color: AppColors.loss, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(server, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            const Text(
              'EC2 may be stopped or IP changed. Check AWS console for current Public IP.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrepSection extends StatelessWidget {
  const _PrepSection({required this.prep});

  final AsyncValue<Map<String, dynamic>> prep;

  @override
  Widget build(BuildContext context) {
    return prep.when(
      data: (p) {
        final title = p['title']?.toString() ?? 'Market Prep';
        final indices = p['indices'] as Map<String, dynamic>? ?? {};
        final options = p['options_map'] as Map<String, dynamic>? ?? {};
        final watch = p['watchlist'] as List<dynamic>? ?? [];
        final news = p['news_digest'] as List<dynamic>? ?? [];
        final sectors = p['sector_heatmap'] as List<dynamic>? ?? [];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: AlphaSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  p['message']?.toString() ?? 'Waiting for confluence ≥70 setups.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (news.isNotEmpty) ...[
                  const Text('Top News', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ...news.take(3).map((n) {
                    final m = Map<String, dynamic>.from(n as Map);
                    return Text(
                      '• ${m['headline']} (${m['sentiment']})',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
                if (sectors.isNotEmpty) ...[
                  const Text('Sector Heat', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ...sectors.map((s) {
                    final m = Map<String, dynamic>.from(s as Map);
                    return Text(
                      '${m['sector']}: ${m['trend']} · ${m['oi_flow']} · ${m['preferred']}',
                      style: const TextStyle(fontSize: 11),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
                ...indices.entries.map((e) {
                  final d = Map<String, dynamic>.from(e.value as Map);
                  final o = Map<String, dynamic>.from((options[e.key] as Map?) ?? {});
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${e.key} ${d['spot']} · ${d['trend']} · PCR ${o['pcr']} · Call ${o['call_wall']} · Put ${o['put_wall']}',
                      style: const TextStyle(fontSize: 11, height: 1.35),
                    ),
                  );
                }),
                if (watch.isNotEmpty) ...[
                  const Divider(height: 20),
                  const Text('Watchlist', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...watch.take(5).map((w) {
                    final m = Map<String, dynamic>.from(w as Map);
                    return Text('• ${m['note']}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted));
                  }),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _OfflineHelp extends StatelessWidget {
  const _OfflineHelp({required this.server, required this.error, required this.onRetry});

  final String server;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.loss),
          const SizedBox(height: 16),
          const Text('Cannot reach server', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(server, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(
            AppErrorView.friendlyMessage(error),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
        ],
      ),
    );
  }
}

class _AlphaSignalCard extends StatelessWidget {
  const _AlphaSignalCard({required this.signal});

  final Map<String, dynamic> signal;

  Color get _tierColor => switch (signal['tier']?.toString()) {
        'A+' => AppColors.profit,
        'A' => AppColors.accent,
        _ => AppColors.warn,
      };

  @override
  Widget build(BuildContext context) {
    final formatted = signal['formatted']?.toString() ?? '';
    return AlphaSurface(
      padding: const EdgeInsets.all(14),
      accent: _tierColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _tierColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _tierColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${signal['tier']} · ${signal['confluence_score']}/100',
                  style: TextStyle(color: _tierColor, fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: formatted.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: formatted));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Signal copied')),
                        );
                      },
              ),
            ],
          ),
          Text(
            '${signal['instrument']} · ${signal['strategy']} · ${signal['strikes']}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(signal['entry_zone']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            'Risk ₹${signal['risk_inr']} · ${signal['lots']} lot(s) · SL: ${signal['sl_rule']}',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          if (formatted.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: AppColors.surface,
                  builder: (_) => DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.85,
                    builder: (_, c) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: ListView(
                        controller: c,
                        children: [
                          const Text('Alpha Signal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          SelectableText(formatted, style: const TextStyle(fontSize: 12, height: 1.4)),
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: const Text('View full signal card'),
            ),
          ],
        ],
      ),
    );
  }
}
