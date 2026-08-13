import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/market_mode.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/claude_service.dart';
import '../services/notification_service.dart';

const _storage = FlutterSecureStorage();
const _notifKey = 'notifications_enabled';
const _claudeKeyKey = 'claude_api_key';
const _aiEnabledKey = 'ai_analysis_enabled';
const _marketModeKey = 'market_mode';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final claudeServiceProvider = Provider<ClaudeService>((ref) => ClaudeService());

final cryptoCredentialsProvider = FutureProvider<CryptoCredentialsStatus>((ref) async {
  final data = await ref.watch(apiServiceProvider).getCryptoCredentialsStatus();
  return CryptoCredentialsStatus.fromJson(data);
});

final marketModeProvider = StateNotifierProvider<MarketModeNotifier, MarketMode>((ref) {
  return MarketModeNotifier();
});

class MarketModeNotifier extends StateNotifier<MarketMode> {
  MarketModeNotifier() : super(MarketMode.indian) {
    _load();
  }

  Future<void> _load() async {
    final v = await _storage.read(key: _marketModeKey);
    state = MarketMode.fromString(v);
  }

  Future<void> setMode(MarketMode mode) async {
    state = mode;
    await _storage.write(key: _marketModeKey, value: mode.storageValue);
  }
}

final aiAnalysisEnabledProvider =
    StateNotifierProvider<AiAnalysisEnabledNotifier, bool>((ref) {
  return AiAnalysisEnabledNotifier();
});

class AiAnalysisEnabledNotifier extends StateNotifier<bool> {
  AiAnalysisEnabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final v = await _storage.read(key: _aiEnabledKey);
    state = v == 'true';
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    await _storage.write(key: _aiEnabledKey, value: value.toString());
  }
}

final claudeApiKeyProvider = FutureProvider<String>((ref) async {
  return await _storage.read(key: _claudeKeyKey) ?? '';
});

final signalAiInsightProvider =
    FutureProvider.family<String, SignalModel>((ref, signal) async {
  final enabled = ref.watch(aiAnalysisEnabledProvider);
  if (!enabled) return '';

  final apiKey = await ref.watch(claudeApiKeyProvider.future);
  if (apiKey.trim().isEmpty) {
    throw Exception('Add Claude API key in Settings');
  }

  final headlines = await ref.watch(apiServiceProvider).getMarketNews();
  return ref.watch(claudeServiceProvider).analyzeSignal(
        apiKey: apiKey.trim(),
        signal: signal,
        headlines: headlines,
      );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});

final notificationsEnabledProvider =
    StateNotifierProvider<NotificationsEnabledNotifier, bool>((ref) {
  return NotificationsEnabledNotifier();
});

class NotificationsEnabledNotifier extends StateNotifier<bool> {
  NotificationsEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final v = await _storage.read(key: _notifKey);
    if (v != null) state = v == 'true';
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    await _storage.write(key: _notifKey, value: value.toString());
    if (value) {
      await NotificationService.instance.requestPermission();
    }
  }
}

final healthProvider = FutureProvider((ref) => ref.watch(apiServiceProvider).getHealth());

final tradingSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(apiServiceProvider).getTradingSettings();
});

final setupsProvider = FutureProvider((ref) => ref.watch(apiServiceProvider).getSetups());

final journalProvider = FutureProvider((ref) => ref.watch(apiServiceProvider).getJournal());

final signalWsProvider = Provider<SignalWebSocket>((ref) {
  final ws = SignalWebSocket();
  ws.connect();
  ref.onDispose(ws.dispose);
  return ws;
});

final livePriceWsProvider = Provider<LivePriceWebSocket>((ref) {
  final ws = LivePriceWebSocket();
  ws.connect();
  ref.onDispose(ws.dispose);
  return ws;
});

final activeSignalsProvider = StreamProvider<List<SignalModel>>((ref) {
  final ws = ref.watch(signalWsProvider);
  final signals = <String, SignalModel>{};
  return ws.stream.map((s) {
    signals['${s.setupName}:${s.instrument}'] = s;
    return signals.values.toList();
  });
});

final livePricesProvider = StreamProvider<Map<String, double>>((ref) {
  return ref.watch(livePriceWsProvider).stream;
});

final candlesProvider = FutureProvider.family((ref, (String, String) args) {
  final (instrument, interval) = args;
  final mode = ref.watch(marketModeProvider);
  if (mode == MarketMode.crypto) {
    return ref.watch(apiServiceProvider).getCryptoCandles(symbol: instrument, interval: interval);
  }
  return ref.watch(apiServiceProvider).getCandles(instrument: instrument, interval: interval);
});

final cryptoPricesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(apiServiceProvider).getCryptoPrices();
});

final cryptoBalancesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(apiServiceProvider).getCryptoBalances();
});

final cryptoTradesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, symbol) async {
  return ref.watch(apiServiceProvider).getCryptoTrades(symbol: symbol);
});

/// Listens to WS and fires phone notifications on TAKE signals.
final tradeAlertListenerProvider = Provider<void>((ref) {
    // Indian market only — crypto TAKE alerts when crypto signals ship.
    final mode = ref.watch(marketModeProvider);
    if (mode != MarketMode.indian) return;

    final enabled = ref.watch(notificationsEnabledProvider);
  final notifications = ref.watch(notificationServiceProvider);
  final ws = ref.watch(signalWsProvider);

  final sub = ws.stream.listen((signal) {
    if (enabled && signal.tradeDecision == 'TAKE') {
      notifications.showTakeTradeAlert(signal);
    }
  });
  ref.onDispose(sub.cancel);
});
