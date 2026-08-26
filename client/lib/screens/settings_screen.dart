import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../providers/app_providers.dart';
import '../services/claude_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _storage = FlutterSecureStorage();
  final _riskCtrl = TextEditingController(text: '1.0');
  final _capitalCtrl = TextEditingController(text: '20000');
  String _tradingStyle = 'hybrid';
  final _smartApiKeyCtrl = TextEditingController();
  final _claudeKeyCtrl = TextEditingController();
  bool _testingClaude = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _riskCtrl.dispose();
    _capitalCtrl.dispose();
    _smartApiKeyCtrl.dispose();
    _claudeKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _smartApiKeyCtrl.text = await _storage.read(key: 'smartapi_api_key') ?? '';
    _claudeKeyCtrl.text = await _storage.read(key: 'claude_api_key') ?? '';
    _riskCtrl.text = await _storage.read(key: 'risk_percent') ?? '1.0';
    if (mounted) setState(() {});
  }

  Future<void> _saveLocal() async {
    await _storage.write(key: 'smartapi_api_key', value: _smartApiKeyCtrl.text.trim());
    await _storage.write(key: 'claude_api_key', value: _claudeKeyCtrl.text.trim());
    await _storage.write(key: 'risk_percent', value: _riskCtrl.text.trim());
    ref.invalidate(claudeApiKeyProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone settings saved')),
      );
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

  Future<void> _updateTradingSettings(Map<String, dynamic> updates, {bool confirmLive = false}) async {
    if (confirmLive && updates['live_execution_enabled'] == true) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable live trading?'),
          content: const Text(
            'Real money orders will be sent via SmartAPI. '
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
      await ref.read(apiServiceProvider).updateTradingSettings(updates);
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

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(healthProvider);
    final notifEnabled = ref.watch(notificationsEnabledProvider);
    final aiEnabled = ref.watch(aiAnalysisEnabledProvider);
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
          'Paper vs live trading for NSE/BSE options on your backend.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final settings = tradingSettings.maybeWhen(
              data: (t) => t,
              orElse: () => defaultTradingSettings,
            );
            if (tradingSettings.hasValue) {
              _riskCtrl.text = (settings['risk_percent'] ?? 1.0).toString();
              _capitalCtrl.text = (settings['trading_capital_inr'] ?? 20000).toString();
              _tradingStyle = settings['trading_style'] as String? ?? 'hybrid';
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tradingSettings.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kill switch'),
                  subtitle: const Text('Emergency stop — blocks all orders'),
                  value: settings['kill_switch'] as bool? ?? false,
                  onChanged: (v) => _updateTradingSettings({'kill_switch': v}),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Paper trading'),
                  subtitle: const Text('Simulate options orders (no real money)'),
                  value: settings['paper_trading'] as bool? ?? true,
                  onChanged: (v) => _updateTradingSettings({'paper_trading': v}),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Live trading'),
                  subtitle: const Text('Send real SmartAPI orders'),
                  value: settings['live_execution_enabled'] as bool? ?? false,
                  onChanged: (v) => _updateTradingSettings({'live_execution_enabled': v}, confirmLive: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _capitalCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Trading capital (₹)',
                    hintText: '20000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _tradingStyle,
                  decoration: const InputDecoration(
                    labelText: 'Trading style',
                    helperText: 'Hybrid = scalp T1 or hold 2–4 weeks',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'scalp', child: Text('Scalp — quick exits')),
                    DropdownMenuItem(value: 'swing', child: Text('Swing — hold weeks')),
                    DropdownMenuItem(value: 'hybrid', child: Text('Hybrid — scalp + swing')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _tradingStyle = v);
                  },
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    final capital = double.tryParse(_capitalCtrl.text.trim());
                    final risk = double.tryParse(_riskCtrl.text.trim());
                    if (capital == null || capital < 5000) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Capital must be at least ₹5,000')),
                      );
                      return;
                    }
                    if (risk == null || risk < 0.1 || risk > 3) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Risk must be 0.1%–3%')),
                      );
                      return;
                    }
                    await _updateTradingSettings({
                      'trading_capital_inr': capital,
                      'trading_style': _tradingStyle,
                      'risk_percent': risk,
                    });
                  },
                  child: const Text('Save capital & style'),
                ),
              ],
            );
          },
        ),
        const Divider(),
        Text('AI market analysis', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Claude key stays on this phone. AI reads live news + signal context.',
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
            final smartApiOk = h.smartapi?['connected'] == true;
            return GlassErrorCard(
              title: h.status == 'ok' ? 'Backend connected' : 'Backend degraded',
              message: smartApiOk
                  ? 'Trading: ${trading['paper_trading'] == true ? 'paper' : 'live'}'
                  : 'SmartAPI not connected',
              onRetry: () => ref.invalidate(healthProvider),
            );
          },
          loading: () => const LinearProgressIndicator(color: AppColors.accent),
          error: (e, _) => GlassErrorCard(
            title: 'Backend offline',
            message: AppErrorView.friendlyMessage(e),
            onRetry: () => ref.invalidate(healthProvider),
          ),
        ),
      ],
    );
  }
}
