import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Set<String> _notifiedKeys = {};
  bool _initialized = false;

  static const _channelId = 'trade_alerts';
  static const _channelName = 'Trade Alerts';
  static const _channelDesc = 'TAKE trade signals with entry, exit, win rate';

  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(settings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return true;
  }

  Future<void> showTakeTradeAlert(SignalModel signal) async {
    if (!_initialized) await init();

    final key = _signalKey(signal);
    if (_notifiedKeys.contains(key)) return;
    _notifiedKeys.add(key);
    if (_notifiedKeys.length > 50) {
      _notifiedKeys.remove(_notifiedKeys.first);
    }

    final winRate = signal.backtestStats['win_rate'];
    final winStr = winRate != null ? '$winRate%' : '—';
    final optionType = signal.direction == 'bearish' ? 'PE' : 'CE';
    final target = signal.underlyingTarget.isNotEmpty
        ? signal.underlyingTarget[0].toStringAsFixed(0)
        : '—';

    final title = 'TAKE TRADE — ${signal.instrument}';
    final body = StringBuffer()
      ..write('${signal.setupName.replaceAll('_', ' ')} · $optionType\n')
      ..write('Win $winStr · Entry ${signal.underlyingEntry.toStringAsFixed(0)}')
      ..write(' · Stop ${signal.underlyingStopLoss.toStringAsFixed(0)}')
      ..write(' · Target $target')
      ..write(' · R:R ${signal.riskReward.toStringAsFixed(1)}');

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'TAKE trade alert',
        styleInformation: BigTextStyleInformation(body.toString()),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      key.hashCode,
      title,
      body.toString(),
      details,
    );
  }

  String _signalKey(SignalModel s) =>
      '${s.setupName}:${s.instrument}:${s.underlyingEntry.toStringAsFixed(0)}:${s.tradeDecision}';
}
