import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

const _storage = FlutterSecureStorage();
const _notifKey = 'notifications_enabled';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

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
