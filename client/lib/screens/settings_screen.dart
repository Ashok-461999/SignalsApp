import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../models/market_mode.dart';
import '../providers/app_providers.dart';
import '../services/claude_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _storage = FlutterSecureStorage();
  final _riskCtrl = TextEditingController(text: '1.0');
  final _smartApiKeyCtrl = TextEditingController();
  final _claudeKeyCtrl = TextEditingController();
  final _cryptoKeyCtrl = TextEditingController();
  final _cryptoSecretCtrl = TextEditingController();
  final _cryptoPassphraseCtrl = TextEditingController();
  CryptoExchange _cryptoExchange = CryptoExchange.binance;
  bool _testingClaude = false;
  bool _testingCrypto = false;
  bool _savingCrypto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _riskCtrl.dispose();
    _smartApiKeyCtrl.dispose();
    _claudeKeyCtrl.dispose();
    _cryptoKeyCtrl.dispose();
    _cryptoSecretCtrl.dispose();
    _cryptoPassphraseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _smartApiKeyCtrl.text = await _storage.read(key: 'smartapi_api_key') ?? '';
    _claudeKeyCtrl.text = await _storage.read(key: 'claude_api_key') ?? '';
    _riskCtrl.text = await _storage.read(key: 'risk_percent') ?? '1.0';
    try {
      final status = await ref.read(apiServiceProvider).getCryptoCredentialsStatus();
      _cryptoExchange = CryptoExchange.fromString(status['exchange'] as String?);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveLocal() async {
    await _storage.write(key: 'smartapi_api_key', value: _smartApiKeyCtrl.text.trim());
    await _storage.write(key: 'claude_api_key', value: _claudeKeyCtrl.text.trim());
    await _storage.write(key: 'risk_percent', value: _riskCtrl.text.trim());
    ref.invalidate(claudeApiKeyProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone settings saved (Claude key stays on device)')),
      );
    }
  }

  Future<void> _saveCryptoToBackend() async {
    final key = _cryptoKeyCtrl.text.trim();
    final secret = _cryptoSecretCtrl.text.trim();
    if (key.isEmpty || secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter API key and secret')),
      );
      return;
    }
    setState(() => _savingCrypto = true);
    try {
      await ref.read(apiServiceProvider).saveCryptoCredentials(
            exchange: _cryptoExchange.name,
            apiKey: key,
            apiSecret: secret,
            passphrase: _cryptoPassphraseCtrl.text.trim(),
          );
      _cryptoKeyCtrl.clear();
      _cryptoSecretCtrl.clear();
      _cryptoPassphraseCtrl.clear();
      ref.invalidate(cryptoCredentialsProvider);
      ref.invalidate(cryptoBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crypto keys saved on server (encrypted)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _savingCrypto = false);
    }
  }

  Future<void> _testClaudeKey() async {
    final key = _claudeKeyCtrl.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste your Claude API key first')),
      );
      return;
    }
    setState(() => _testingClaude = true);
    try {
      final ok = await ClaudeService().testApiKey(key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Claude API key works ✓' : 'Key test failed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Claude error: $e')));
    } finally {
      if (mounted) setState(() => _testingClaude = false);
    }
  }

  Future<void> _testCryptoKeys() async {
    final key = _cryptoKeyCtrl.text.trim();
    final secret = _cryptoSecretCtrl.text.trim();
    if (key.isEmpty || secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter API key and secret to test')),
      );
      return;
    }
    setState(() => _testingCrypto = true);
    try {
      final msg = await ref.read(apiServiceProvider).testCryptoCredentials(
            exchange: _cryptoExchange.name,
            apiKey: key,
            apiSecret: secret,
            passphrase: _cryptoPassphraseCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Crypto API error: $e')),
      );
    } finally {
      if (mounted) setState(() => _testingCrypto = false);
    }
  }

  Future<void> _updateTradingSetting(String key, bool value, {bool confirmLive = false}) async {
    if (confirmLive && value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable live trading?'),
          content: const Text(
            'Real money orders will be sent to the exchange. '
            'Make sure API keys and risk limits are correct.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enable')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(apiServiceProvider).updateTradingSettings({key: value});
      ref.invalidate(tradingSettingsProvider);
      ref.invalidate(healthProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trading settings updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _clearCryptoKeys() async {
    try {
      await ref.read(apiServiceProvider).clearCryptoCredentials();
      ref.invalidate(cryptoCredentialsProvider);
      ref.invalidate(cryptoBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crypto keys removed from server')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(healthProvider);
    final notifEnabled = ref.watch(notificationsEnabledProvider);
    final aiEnabled = ref.watch(aiAnalysisEnabledProvider);
    final cryptoCreds = ref.watch(cryptoCredentialsProvider);
    final tradingSettings = ref.watch(tradingSettingsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Trade notifications'),
          subtitle: const Text('Alert on TAKE — entry, stop, target'),
          value: notifEnabled,
          onChanged: (v) => ref.read(notificationsEnabledProvider.notifier).setEnabled(v),
        ),
        const Divider(),
        Text('Trading modes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Control paper vs live trading on your backend server.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        tradingSettings.when(
          data: (t) => Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kill switch'),
                subtitle: const Text('Emergency stop — blocks all orders'),
                value: t['kill_switch'] as bool? ?? false,
                onChanged: (v) => _updateTradingSetting('kill_switch', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Indian paper trading'),
                subtitle: const Text('Simulate options orders (no real money)'),
                value: t['paper_trading'] as bool? ?? true,
                onChanged: (v) => _updateTradingSetting('paper_trading', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Indian live trading'),
                subtitle: const Text('Send real SmartAPI orders'),
                value: t['live_execution_enabled'] as bool? ?? false,
                onChanged: (v) => _updateTradingSetting('live_execution_enabled', v, confirmLive: true),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Crypto paper trading'),
                subtitle: const Text('Simulate crypto buy/sell'),
                value: t['crypto_paper_trading'] as bool? ?? true,
                onChanged: (v) => _updateTradingSetting('crypto_paper_trading', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Crypto live trading'),
                subtitle: const Text('Send real orders to your exchange'),
                value: t['crypto_live_enabled'] as bool? ?? false,
                onChanged: (v) => _updateTradingSetting('crypto_live_enabled', v, confirmLive: true),
              ),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text('Trading settings: $e', style: const TextStyle(color: AppColors.loss)),
        ),
        const Divider(),
        Text('Crypto exchange API', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Crypto keys are stored encrypted on your backend server. '
          'Only Claude AI key stays on this phone.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<CryptoExchange>(
          initialValue: _cryptoExchange,
          decoration: const InputDecoration(labelText: 'Exchange'),
          items: CryptoExchange.values
              .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
              .toList(),
          onChanged: (v) => setState(() => _cryptoExchange = v ?? CryptoExchange.binance),
        ),
        TextField(
          controller: _cryptoKeyCtrl,
          decoration: const InputDecoration(
            labelText: 'API key',
            hintText: 'Sent to backend — not saved on phone',
          ),
          obscureText: true,
        ),
        TextField(
          controller: _cryptoSecretCtrl,
          decoration: const InputDecoration(
            labelText: 'API secret',
            hintText: 'Encrypted on server',
          ),
          obscureText: true,
        ),
        if (_cryptoExchange == CryptoExchange.bybit)
          TextField(
            controller: _cryptoPassphraseCtrl,
            decoration: const InputDecoration(labelText: 'Passphrase (if required)'),
            obscureText: true,
          ),
        cryptoCreds.when(
          data: (c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              c.configured
                  ? '● Server has ${c.exchange.label} keys ${c.apiKeyHint ?? ''}'
                  : 'No crypto keys on server yet',
              style: TextStyle(
                fontSize: 12,
                color: c.configured ? AppColors.profit : AppColors.textMuted,
              ),
            ),
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        Row(
          children: [
            FilledButton(
              onPressed: _savingCrypto ? null : _saveCryptoToBackend,
              child: _savingCrypto
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save to server'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _testingCrypto ? null : _testCryptoKeys,
              child: _testingCrypto
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Test'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _clearCryptoKeys, child: const Text('Clear')),
          ],
        ),
        const Divider(),
        Text('AI market analysis', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Claude key stays on this phone only. AI reads headlines + signal context.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable Claude AI analysis'),
          subtitle: const Text('Show AI insight on signal detail screen'),
          value: aiEnabled,
          onChanged: (v) => ref.read(aiAnalysisEnabledProvider.notifier).setEnabled(v),
        ),
        TextField(
          controller: _claudeKeyCtrl,
          decoration: const InputDecoration(
            labelText: 'Claude API key (phone only)',
            hintText: 'sk-ant-api03-...',
          ),
          obscureText: true,
        ),
        Row(
          children: [
            OutlinedButton(
              onPressed: _testingClaude ? null : _testClaudeKey,
              child: _testingClaude
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Test Claude key'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                await _storage.delete(key: 'claude_api_key');
                _claudeKeyCtrl.clear();
                ref.invalidate(claudeApiKeyProvider);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Claude key removed from phone')),
                );
              },
              child: const Text('Clear key'),
            ),
          ],
        ),
        const Divider(),
        Text('Indian market', style: Theme.of(context).textTheme.titleMedium),
        Text('Backend: ${AppConfig.apiBaseUrl}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: _smartApiKeyCtrl,
          decoration: const InputDecoration(labelText: 'SmartAPI key (local backup)'),
          obscureText: true,
        ),
        TextField(
          controller: _riskCtrl,
          decoration: const InputDecoration(labelText: 'Risk % per trade'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _saveLocal, child: const Text('Save phone settings')),
        const Divider(),
        health.when(
          data: (h) {
            final trading = h.trading ?? <String, dynamic>{};
            final crypto = h.crypto ?? <String, dynamic>{};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Backend status', style: Theme.of(context).textTheme.titleSmall),
                Text('Indian: ${trading['paper_trading'] == true ? 'paper' : 'live'}'),
                Text('Crypto: ${trading['crypto_paper_trading'] == true ? 'paper' : 'live'}'),
                Text('Crypto keys: ${crypto['configured'] == true ? 'configured' : 'not set'}'),
                Text('Kill switch: ${trading['kill_switch']}'),
              ],
            );
          },
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('$e'),
        ),
      ],
    );
  }
}
