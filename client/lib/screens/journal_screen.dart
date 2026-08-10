import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journal = ref.watch(journalProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(journalProvider)),
        ],
      ),
      body: journal.when(
        data: (data) {
          final summary = data['summary'] as Map<String, dynamic>? ?? {};
          final entries = (data['entries'] as List<dynamic>? ?? [])
              .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('P&L', '${summary['total_pnl'] ?? 0}'),
                    _stat('Win %', '${summary['win_rate'] ?? 0}'),
                    _stat('Closed', '${summary['closed_trades'] ?? 0}'),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('No journal entries yet'))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (_, i) => _JournalTile(entry: entries[i], ref: ref),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
      );
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.entry, required this.ref});
  final JournalEntry entry;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text('${entry.setupName} · ${entry.instrument}'),
        subtitle: Text('${entry.status} · ${entry.direction}'),
        trailing: Text(entry.pnl != null ? entry.pnl!.toStringAsFixed(0) : '—'),
        onTap: () => _showEditDialog(context),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final fillCtrl = TextEditingController(text: entry.actualFillPrice?.toString() ?? '');
    final exitCtrl = TextEditingController(text: entry.exitPrice?.toString() ?? '');
    final pnlCtrl = TextEditingController(text: entry.pnl?.toString() ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update trade'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: fillCtrl, decoration: const InputDecoration(labelText: 'Fill price')),
            TextField(controller: exitCtrl, decoration: const InputDecoration(labelText: 'Exit price')),
            TextField(controller: pnlCtrl, decoration: const InputDecoration(labelText: 'P&L')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await ref.read(apiServiceProvider).updateJournal(entry.id, {
                if (fillCtrl.text.isNotEmpty) 'actual_fill_price': double.parse(fillCtrl.text),
                if (exitCtrl.text.isNotEmpty) 'exit_price': double.parse(exitCtrl.text),
                if (pnlCtrl.text.isNotEmpty) 'pnl': double.parse(pnlCtrl.text),
                'status': 'closed',
              });
              ref.invalidate(journalProvider);
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
