import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../screens/chart_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';

class CryptoWatchlistScreen extends ConsumerWidget {
  const CryptoWatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prices = ref.watch(cryptoPricesProvider);
    final creds = ref.watch(cryptoCredentialsProvider);
    final balances = ref.watch(cryptoBalancesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(cryptoPricesProvider);
        ref.invalidate(cryptoBalancesProvider);
        ref.invalidate(cryptoCredentialsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          creds.when(
            data: (c) => _StatusBanner(configured: c.configured, exchange: c.exchange.label),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const _StatusBanner(configured: false, exchange: ''),
          ),
          const SizedBox(height: 12),
          balances.when(
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final top = list.take(4).toList();
              return _BalancesCard(balances: top);
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          prices.when(
            data: (list) => Column(
              children: list.map((p) {
                final symbol = p['symbol'] as String? ?? '';
                return _CryptoCard(
                  symbol: symbol,
                  name: p['name'] as String? ?? symbol,
                  price: (p['price'] as num?)?.toDouble() ?? 0,
                  changePct: (p['change_pct_24h'] as num?)?.toDouble() ?? 0,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChartScreen(instrument: symbol),
                    ),
                  ),
                  onTrade: () => _showTradeSheet(context, ref, symbol),
                );
              }).toList(),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
            ),
            error: (e, _) => AppErrorView(
              title: 'Crypto prices unavailable',
              message: AppErrorView.friendlyMessage(e),
              compact: true,
              onRetry: () => ref.invalidate(cryptoPricesProvider),
            ),
          ),
        ],
      ),
    );
  }

  void _showTradeSheet(BuildContext context, WidgetRef ref, String symbol) {
    final qtyCtrl = TextEditingController(text: '0.001');
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Trade $symbol', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'Paper mode by default. Live orders need server flag + API keys.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.profit),
                    onPressed: () => _placeOrder(ctx, ref, symbol, 'BUY', qtyCtrl.text),
                    child: const Text('Buy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.loss),
                    onPressed: () => _placeOrder(ctx, ref, symbol, 'SELL', qtyCtrl.text),
                    child: const Text('Sell'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _placeOrder(
    BuildContext context,
    WidgetRef ref,
    String symbol,
    String side,
    String qtyText,
  ) async {
    final qty = double.tryParse(qtyText);
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity')),
      );
      return;
    }
    try {
      final result = await ref.read(apiServiceProvider).placeCryptoOrder(
            symbol: symbol,
            side: side,
            quantity: qty,
          );
      if (!context.mounted) return;
      Navigator.pop(context);
      ref.invalidate(cryptoBalancesProvider);
      ref.invalidate(cryptoTradesProvider(symbol));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] as String? ?? 'Order placed')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order failed: $e')));
    }
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.configured, required this.exchange});

  final bool configured;
  final String exchange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (configured ? AppColors.profit : AppColors.warn).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (configured ? AppColors.profit : AppColors.warn).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            configured ? Icons.check_circle_outline : Icons.info_outline_rounded,
            color: configured ? AppColors.profit : AppColors.warn,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              configured
                  ? '$exchange API on server — live prices & paper trades active.'
                  : 'Add crypto API keys in Settings → saved on backend server.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancesCard extends StatelessWidget {
  const _BalancesCard({required this.balances});

  final List<Map<String, dynamic>> balances;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Balances', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...balances.map(
            (b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(b['asset'] as String? ?? ''),
                  Text(
                    ((b['free'] as num?)?.toDouble() ?? 0).toStringAsFixed(4),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CryptoCard extends StatelessWidget {
  const _CryptoCard({
    required this.symbol,
    required this.name,
    required this.price,
    required this.changePct,
    required this.onTap,
    required this.onTrade,
  });

  final String symbol;
  final String name;
  final double price;
  final double changePct;
  final VoidCallback onTap;
  final VoidCallback onTrade;

  @override
  Widget build(BuildContext context) {
    final up = changePct >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7931A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.currency_bitcoin_rounded,
                    color: symbol == 'BTC' ? const Color(0xFFF7931A) : AppColors.accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$symbol/USDT',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      Text(name, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price > 0 ? '\$${price.toStringAsFixed(price < 1 ? 4 : 2)}' : '—',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      price > 0 ? '${up ? '+' : ''}${changePct.toStringAsFixed(2)}%' : '24h —',
                      style: TextStyle(
                        color: up ? AppColors.profit : AppColors.loss,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.accent),
                  onPressed: onTrade,
                  tooltip: 'Trade',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
