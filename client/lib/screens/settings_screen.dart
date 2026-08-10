import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  final _riskCtrl = TextEditingController(text: '1.0');
  String _apiKey = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _apiKey = await _storage.read(key: 'smartapi_api_key') ?? '';
    _riskCtrl.text = await _storage.read(key: 'risk_percent') ?? '1.0';
    setState(() {});
  }

  Future<void> _save() async {
    await _storage.write(key: 'smartapi_api_key', value: _apiKey);
    await _storage.write(key: 'risk_percent', value: _riskCtrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved locally')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(healthProvider);
    final notifEnabled = ref.watch(notificationsEnabledProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Trade notifications'),
            subtitle: const Text('Alert on TAKE — win %, entry, stop, target'),
            value: notifEnabled,
            onChanged: (v) => ref.read(notificationsEnabledProvider.notifier).setEnabled(v),
          ),
          const Divider(),
          Text('API: ${AppConfig.apiBaseUrl}'),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(labelText: 'SmartAPI Key (stored securely)'),
            obscureText: true,
            controller: TextEditingController(text: _apiKey),
            onChanged: (v) => _apiKey = v,
          ),
          TextField(
            controller: _riskCtrl,
            decoration: const InputDecoration(labelText: 'Risk % per trade'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const Divider(),
          health.when(
            data: (h) {
              final trading = h.trading ?? <String, dynamic>{};
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paper trading: ${trading['paper_trading']}'),
                  Text('Live execution: ${trading['live_execution_enabled']}'),
                  Text('Kill switch: ${trading['kill_switch']}'),
                ],
              );
            },
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
        ],
      ),
    );
  }
}
