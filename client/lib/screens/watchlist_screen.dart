import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prices = ref.watch(livePricesProvider);
    const indices = ['NIFTY', 'BANKNIFTY', 'SENSEX'];

    return Scaffold(
      appBar: AppBar(title: const Text('Watchlist')),
      body: prices.when(
        data: (p) => ListView(
          children: indices.map((name) {
            final price = p[name];
            return ListTile(
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(
                price != null ? price.toStringAsFixed(1) : '—',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: const Text('5m live'),
            );
          }).toList(),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Connect to backend for live prices\n$e')),
      ),
    );
  }
}
