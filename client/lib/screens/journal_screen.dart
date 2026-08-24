import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_mode.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../widgets/status_widgets.dart';

enum _TradeFilter { all, open, closed, wins, losses }

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  _TradeFilter _filter = _TradeFilter.all;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(marketModeProvider);
    if (mode == MarketMode.crypto) {
      return const _CryptoTradesJournal();
    }

    final journal = ref.watch(journalProvider);

    return journal.when(
        data: (data) {
          final summary = JournalSummary.fromJson(
            data['summary'] as Map<String, dynamic>? ?? {},
          );
          final entries = (data['entries'] as List<dynamic>? ?? [])
              .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          final filtered = _applyFilter(entries);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(journalProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      const Text('P&L & Journal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: () => ref.invalidate(journalProvider),
                      ),
                    ],
                  ),
                ),
                _PnlDashboard(summary: summary),
                const SizedBox(height: 8),
                _FilterChips(
                  filter: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No trades yet.\nApprove a TAKE signal to start tracking.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...filtered.map((e) => _JournalTile(entry: e, ref: ref)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          title: 'Cannot load journal',
          message: AppErrorView.friendlyMessage(e),
          onRetry: () => ref.invalidate(journalProvider),
        ),
    );
  }

  List<JournalEntry> _applyFilter(List<JournalEntry> entries) {
    return switch (_filter) {
      _TradeFilter.open => entries.where((e) => e.pnl == null && e.status != 'rejected').toList(),
      _TradeFilter.closed => entries.where((e) => e.pnl != null).toList(),
      _TradeFilter.wins => entries.where((e) => e.pnl != null && e.pnl! > 0).toList(),
      _TradeFilter.losses => entries.where((e) => e.pnl != null && e.pnl! < 0).toList(),
      _ => entries,
    };
  }
}

String _inr(num value) => formatInr(value);

Color _pnlColor(num? pnl) {
  if (pnl == null) return AppColors.textMuted;
  if (pnl > 0) return AppColors.profit;
  if (pnl < 0) return AppColors.loss;
  return AppColors.textMuted;
}

class _PnlDashboard extends StatelessWidget {
  const _PnlDashboard({required this.summary});
  final JournalSummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: _pnlColor(summary.totalPnl).withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Total P&L', style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    _inr(summary.totalPnl),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _pnlColor(summary.totalPnl),
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _miniStat('Today', _inr(summary.todayPnl), _pnlColor(summary.todayPnl)),
                      _miniStat('This week', _inr(summary.weekPnl), _pnlColor(summary.weekPnl)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statCard('Wins', '${summary.wins}', Colors.green.shade700)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Losses', '${summary.losses}', Colors.red.shade700)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Open', '${summary.openTrades}', Colors.blue.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statCard('Win %', '${summary.winRate.toStringAsFixed(0)}%', null)),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  'Profit factor',
                  summary.profitFactor?.toStringAsFixed(2) ?? '—',
                  null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Avg/trade', _inr(summary.expectancy), _pnlColor(summary.expectancy))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statCard('Avg win', _inr(summary.avgWin), Colors.green.shade700)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Avg loss', _inr(summary.avgLoss), Colors.red.shade700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ],
      );

  Widget _statCard(String label, String value, Color? color) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
              ),
            ],
          ),
        ),
      );
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.filter, required this.onChanged});
  final _TradeFilter filter;
  final ValueChanged<_TradeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: _TradeFilter.values.map((f) {
          final label = switch (f) {
            _TradeFilter.all => 'All',
            _TradeFilter.open => 'Open',
            _TradeFilter.closed => 'Closed',
            _TradeFilter.wins => 'Wins',
            _TradeFilter.losses => 'Losses',
          };
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: filter == f,
              onSelected: (_) => onChanged(f),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.entry, required this.ref});
  final JournalEntry entry;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isOpen = entry.pnl == null && entry.status != 'rejected';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _pnlColor(entry.pnl).withValues(alpha: 0.15),
          child: Icon(
            entry.pnl == null
                ? (isOpen ? Icons.hourglass_top : Icons.block)
                : (entry.pnl! >= 0 ? Icons.trending_up : Icons.trending_down),
            color: _pnlColor(entry.pnl),
            size: 20,
          ),
        ),
        title: Text('${entry.setupName} · ${entry.instrument}'),
        subtitle: Text(
          '${entry.direction} · ${entry.status}'
          '${entry.suggestedStrike != null ? ' · ${entry.suggestedStrike!.toStringAsFixed(0)}' : ''}'
          '${entry.plannedSize > 0 ? ' · ${entry.plannedSize} lot(s)' : ''}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              entry.pnl != null ? _inr(entry.pnl!) : (isOpen ? 'OPEN' : '—'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _pnlColor(entry.pnl),
              ),
            ),
            if (entry.actualFillPrice != null)
              Text('in ${entry.actualFillPrice!.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11)),
          ],
        ),
        onTap: () => _showEditDialog(context),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final fillCtrl = TextEditingController(text: entry.actualFillPrice?.toString() ?? '');
    final exitCtrl = TextEditingController(text: entry.exitPrice?.toString() ?? '');
    final pnlCtrl = TextEditingController(text: entry.pnl?.toString() ?? '');
    final notesCtrl = TextEditingController(text: entry.notes);
    final lotsCtrl = TextEditingController(text: entry.plannedSize.toString());

    void autoCalc() {
      final fill = double.tryParse(fillCtrl.text);
      final exit = double.tryParse(exitCtrl.text);
      final lots = int.tryParse(lotsCtrl.text) ?? entry.plannedSize;
      if (fill == null || exit == null) return;
      final lotSize = switch (entry.instrument.toUpperCase()) {
        'BANKNIFTY' => 15,
        'FINNIFTY' => 40,
        'SENSEX' => 10,
        _ => 25,
      };
      final pnl = (exit - fill) * lotSize * lots;
      pnlCtrl.text = pnl.toStringAsFixed(0);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${entry.setupName} · ${entry.instrument}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Entry plan: ${entry.underlyingEntry.toStringAsFixed(1)} → SL ${entry.underlyingStopLoss.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lotsCtrl,
                decoration: const InputDecoration(labelText: 'Lots traded'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: fillCtrl,
                decoration: const InputDecoration(labelText: 'Premium paid (entry)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => autoCalc(),
              ),
              TextField(
                controller: exitCtrl,
                decoration: const InputDecoration(labelText: 'Premium received (exit)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => autoCalc(),
              ),
              TextField(
                controller: pnlCtrl,
                decoration: const InputDecoration(
                  labelText: 'P&L (₹) — auto-calculated or override',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              ),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (what went right/wrong)'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: autoCalc,
                icon: const Icon(Icons.calculate),
                label: const Text('Recalculate P&L'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final payload = <String, dynamic>{
                if (fillCtrl.text.isNotEmpty) 'actual_fill_price': double.parse(fillCtrl.text),
                if (exitCtrl.text.isNotEmpty) 'exit_price': double.parse(exitCtrl.text),
                if (pnlCtrl.text.isNotEmpty) 'pnl': double.parse(pnlCtrl.text),
                'notes': notesCtrl.text,
                'status': 'closed',
              };
              await ref.read(apiServiceProvider).updateJournal(entry.id, payload);
              ref.invalidate(journalProvider);
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save & close trade'),
          ),
        ],
      ),
    );
  }
}

class _CryptoTradesJournal extends ConsumerStatefulWidget {
  const _CryptoTradesJournal();

  @override
  ConsumerState<_CryptoTradesJournal> createState() => _CryptoTradesJournalState();
}

class _CryptoTradesJournalState extends ConsumerState<_CryptoTradesJournal> {
  String _symbol = 'BTC';

  @override
  Widget build(BuildContext context) {
    final trades = ref.watch(cryptoTradesProvider(_symbol));
    final balances = ref.watch(cryptoBalancesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(cryptoTradesProvider(_symbol));
        ref.invalidate(cryptoBalancesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const Text('Crypto trades', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Recent fills from your exchange (requires API keys on server).',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          balances.when(
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wallet', style: TextStyle(fontWeight: FontWeight.w700)),
                      ...list.take(6).map(
                            (b) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(b['asset'] as String? ?? ''),
                              trailing: Text(
                                ((b['free'] as num?)?.toDouble() ?? 0).toStringAsFixed(4),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Balances: $e', style: const TextStyle(color: AppColors.loss)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['BTC', 'ETH', 'SOL', 'BNB'].map((s) {
              final selected = _symbol == s;
              return ChoiceChip(
                label: Text(s),
                selected: selected,
                onSelected: (_) => setState(() => _symbol = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          trades.when(
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('No recent trades for $_symbol')),
                );
              }
              return Column(
                children: list.map((t) {
                  final side = (t['side'] as String? ?? '').toUpperCase();
                  final isBuy = side == 'BUY';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        isBuy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        color: isBuy ? AppColors.profit : AppColors.loss,
                      ),
                      title: Text('$side ${t['symbol'] ?? _symbol}'),
                      subtitle: Text(
                        'Qty ${t['quantity']} @ ${t['price']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.loss)),
          ),
        ],
      ),
    );
  }
}
