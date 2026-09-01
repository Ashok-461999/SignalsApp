import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import '../models/news_intel.dart';
import '../services/api_service.dart';
import '../services/claude_service.dart';
import '../services/notification_service.dart';

const _storage = FlutterSecureStorage();
const _notifKey = 'notifications_enabled';
const _claudeKeyKey = 'claude_api_key';
const _aiEnabledKey = 'ai_analysis_enabled';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final claudeServiceProvider = Provider<ClaudeService>((ref) => ClaudeService());

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

const defaultTradingSettings = <String, dynamic>{
  'kill_switch': false,
  'paper_trading': true,
  'live_execution_enabled': false,
  'risk_percent': 1.0,
  'trading_capital_inr': 20000.0,
  'trading_style': 'hybrid',
};

final healthProvider = FutureProvider((ref) => ref.watch(apiServiceProvider).getHealth());

/// Periodically refresh server status so UI recovers after backend restarts.
final healthRefreshProvider = Provider<void>((ref) {
  if (kDebugMode && const bool.fromEnvironment('FLUTTER_TEST')) {
    return;
  }
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    ref.invalidate(healthProvider);
  });
  ref.onDispose(timer.cancel);
});

final tradingSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    return await ref.watch(apiServiceProvider).getTradingSettings();
  } catch (_) {
    return Map<String, dynamic>.from(defaultTradingSettings);
  }
});

final setupsProvider = FutureProvider((ref) => ref.watch(apiServiceProvider).getSetups());

final journalProvider = FutureProvider((ref) => ref.watch(apiServiceProvider).getJournal());

final signalHistoryProvider = FutureProvider<SignalHistoryResponse>((ref) async {
  return ref.watch(apiServiceProvider).getSignalHistory(limit: 80);
});

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

final marketIntelProvider = FutureProvider<MarketIntelResponse>((ref) async {
  return ref.watch(apiServiceProvider).getMarketPredictions();
});

final predictionBySymbolProvider = Provider<Map<String, SymbolPrediction>>((ref) {
  return ref.watch(marketIntelProvider).maybeWhen(
        data: (intel) => {for (final p in intel.predictions) p.symbol: p},
        orElse: () => {},
      );
});

final regimesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    return await ref.watch(apiServiceProvider).getRegimes();
  } catch (_) {
    return {};
  }
});

final alphaSignalsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    return await ref.watch(apiServiceProvider).getAlphaSignals();
  } catch (_) {
    return {'count': 0, 'signals': <dynamic>[]};
  }
});

final activeSignalsProvider = StreamProvider<List<SignalModel>>((ref) async* {
  final api = ref.read(apiServiceProvider);
  final ws = ref.watch(signalWsProvider);
  final cache = <String, SignalModel>{};

  void merge(SignalModel signal) {
    cache['${signal.setupName}:${signal.instrument}'] = signal;
  }

  Future<void> loadFromRest() async {
    final list = await api.getSignalEvaluations();
    for (final signal in list) {
      merge(signal);
    }
  }

  try {
    await loadFromRest();
    yield cache.values.toList();
  } catch (e) {
    if (cache.isNotEmpty) {
      yield cache.values.toList();
    } else {
      rethrow;
    }
  }

  yield* Stream<List<SignalModel>>.multi((controller) {
    final subs = <StreamSubscription<dynamic>>[];
    final pollTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      try {
        await loadFromRest();
        if (!controller.isClosed) {
          controller.add(cache.values.toList());
        }
      } catch (_) {}
    });

    subs.add(ws.stream.listen((signal) {
      merge(signal);
      controller.add(cache.values.toList());
    }));
    subs.add(ws.snapshotReady.listen((_) {
      controller.add(cache.values.toList());
    }));
    controller.onCancel = () {
      pollTimer.cancel();
      for (final sub in subs) {
        sub.cancel();
      }
    };
  });
});

final livePricesProvider = StreamProvider<Map<String, double>>((ref) {
  return _throttleLatest(ref.watch(livePriceWsProvider).stream, const Duration(milliseconds: 300))
      .handleError((_) => <String, double>{});
});

/// Limits UI rebuilds from high-frequency tick updates.
Stream<T> _throttleLatest<T>(Stream<T> input, Duration interval) {
  late final StreamController<T> out;
  Timer? timer;
  T? pending;

  void scheduleFlush() {
    timer ??= Timer(interval, () {
      timer = null;
      if (pending != null && !out.isClosed) {
        out.add(pending as T);
        pending = null;
      }
    });
  }

  out = StreamController<T>(
    onListen: () {
      input.listen(
        (event) {
          pending = event;
          scheduleFlush();
        },
        onError: out.addError,
        onDone: () async {
          timer?.cancel();
          if (pending != null && !out.isClosed) {
            out.add(pending as T);
            pending = null;
          }
          await out.close();
        },
        cancelOnError: false,
      );
    },
  );

  return out.stream;
}

final candlesProvider = FutureProvider.family((ref, (String, String) args) {
  final (instrument, interval) = args;
  return ref.watch(apiServiceProvider).getCandles(instrument: instrument, interval: interval);
});

/// Listens to WS and fires phone notifications on TAKE signals.
final tradeAlertListenerProvider = Provider<void>((ref) {
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
