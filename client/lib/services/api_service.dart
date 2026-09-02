import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../models/candle.dart';
import '../models/models.dart';
import '../models/news_intel.dart';

class ApiService {
  ApiService({Dio? dio}) : _dio = dio ?? _createDio();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        final opts = error.requestOptions;
        final retryCount = (opts.extra['retryCount'] as int?) ?? 0;
        final retriable = error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionError;
        if (retryCount < 1 && retriable) {
          opts.extra['retryCount'] = retryCount + 1;
          await Future<void>.delayed(Duration(milliseconds: 350 * (retryCount + 1)));
          try {
            handler.resolve(await dio.fetch(opts));
            return;
          } catch (_) {}
        }
        handler.next(error);
      },
    ));
    return dio;
  }

  final Dio _dio;

  Future<HealthResponse> getHealth() async {
    final r = await _dio.get<Map<String, dynamic>>('/health');
    return HealthResponse.fromJson(r.data!);
  }

  Future<CandlesResponse> getCandles({
    String instrument = 'NIFTY',
    String segment = 'spot',
    String interval = '5m',
    int limit = 120,
  }) async {
    final r = await _dio.get<Map<String, dynamic>>('/candles', queryParameters: {
      'instrument': instrument,
      'interval': interval,
      'segment': segment,
      'limit': limit,
    });
    return CandlesResponse.fromJson(r.data!);
  }

  Future<Map<String, dynamic>> getSetups() async {
    final r = await _dio.get<Map<String, dynamic>>('/setups');
    return r.data!;
  }

  Future<Map<String, dynamic>> getIvPercentile(String instrument) async {
    final r = await _dio.get<Map<String, dynamic>>('/iv-percentile', queryParameters: {
      'instrument': instrument,
    });
    return r.data!;
  }

  Future<Map<String, dynamic>> getJournal() async {
    final r = await _dio.get<Map<String, dynamic>>('/journal');
    return r.data!;
  }

  Future<List<Map<String, dynamic>>> getMarketNews({int limit = 12}) async {
    final r = await _dio.get<Map<String, dynamic>>('/market/news', queryParameters: {'limit': limit});
    final headlines = r.data?['headlines'] as List<dynamic>? ?? [];
    return headlines.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<JournalEntry> approveSignal(SignalModel signal) async {
    final r = await _dio.post<Map<String, dynamic>>('/journal', data: {
      'setup_name': signal.setupName,
      'instrument': signal.instrument,
      'segment': signal.segment,
      'direction': signal.direction,
      'underlying_entry': signal.underlyingEntry,
      'underlying_stop_loss': signal.underlyingStopLoss,
      'underlying_target': signal.underlyingTarget,
      'suggested_strike': signal.suggestedStrike,
      'suggested_expiry': signal.suggestedExpiry,
      'planned_size': signal.positionSize,
      'status': 'approved',
    });
    return JournalEntry.fromJson(r.data!);
  }

  Future<JournalEntry> rejectSignal(SignalModel signal) async {
    final r = await _dio.post<Map<String, dynamic>>('/journal', data: {
      'setup_name': signal.setupName,
      'instrument': signal.instrument,
      'segment': signal.segment,
      'direction': signal.direction,
      'underlying_entry': signal.underlyingEntry,
      'underlying_stop_loss': signal.underlyingStopLoss,
      'underlying_target': signal.underlyingTarget,
      'status': 'rejected',
      'planned_size': 0,
      'notes': 'Rejected by user',
    });
    return JournalEntry.fromJson(r.data!);
  }

  Future<JournalEntry> updateJournal(int id, Map<String, dynamic> data) async {
    final r = await _dio.patch<Map<String, dynamic>>('/journal/$id', data: data);
    return JournalEntry.fromJson(r.data!);
  }

  Future<List<SignalModel>> getSignalEvaluations() async {
    final r = await _dio.get<Map<String, dynamic>>('/signals/evaluations');
    final evals = r.data?['evaluations'] as List<dynamic>? ?? [];
    final out = <SignalModel>[];
    for (final raw in evals) {
      if (raw is! Map) continue;
      try {
        out.add(SignalModel.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {
        // Skip malformed rows instead of failing the whole feed.
      }
    }
    return out;
  }

  Future<SignalHistoryResponse> getSignalHistory({int limit = 50}) async {
    final r = await _dio.get<Map<String, dynamic>>('/signals/history', queryParameters: {'limit': limit});
    return SignalHistoryResponse.fromJson(r.data ?? {});
  }

  Future<MarketIntelResponse> getMarketPredictions({int limit = 15}) async {
    final r = await _dio.get<Map<String, dynamic>>('/market/predictions', queryParameters: {'limit': limit});
    return MarketIntelResponse.fromJson(r.data ?? {});
  }

  Future<Map<String, dynamic>> getRegimes() async {
    final r = await _dio.get<Map<String, dynamic>>('/signals/regime');
    return r.data ?? {};
  }

  Future<Map<String, dynamic>> getTradingSettings() async {
    final r = await _dio.get<Map<String, dynamic>>('/settings/trading');
    return r.data!;
  }

  Future<Map<String, dynamic>> updateTradingSettings(Map<String, dynamic> data) async {
    final r = await _dio.patch<Map<String, dynamic>>('/settings/trading', data: data);
    return r.data!;
  }

  Future<Map<String, dynamic>> getAlphaSignals() async {
    final r = await _dio.get<Map<String, dynamic>>('/alpha/signals');
    return r.data ?? {};
  }

  Future<Map<String, dynamic>> triggerAlphaScan() async {
    final r = await _dio.post<Map<String, dynamic>>('/alpha/scan');
    return r.data ?? {};
  }

  Future<Map<String, dynamic>> getAlphaPrepReport() async {
    final r = await _dio.get<Map<String, dynamic>>('/alpha/prep');
    return r.data ?? {};
  }

  Future<Map<String, dynamic>> getAlphaStatus() async {
    final r = await _dio.get<Map<String, dynamic>>('/alpha/status');
    return r.data ?? {};
  }
}

class SignalWebSocket {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _controller = StreamController<SignalModel>.broadcast();
  final _snapshotReady = StreamController<void>.broadcast();
  bool _disposed = false;

  Stream<SignalModel> get stream => _controller.stream;
  Stream<void> get snapshotReady => _snapshotReady.stream;

  void connect() {
    _connect();
  }

  void _connect() {
    if (_disposed) return;
    _subscription?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    final uri = Uri.parse('${AppConfig.wsBaseUrl}/signals');
    try {
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        (event) {
          if (_disposed || _controller.isClosed) return;
          try {
            final msg = jsonDecode(event as String) as Map<String, dynamic>;
            if (msg['type'] == 'signal' && msg['data'] != null) {
              _controller.add(SignalModel.fromJson(Map<String, dynamic>.from(msg['data'] as Map)));
            } else if (msg['type'] == 'snapshot') {
              final signals = msg['signals'] as List<dynamic>? ?? [];
              for (final s in signals) {
                if (s is! Map) continue;
                try {
                  _controller.add(SignalModel.fromJson(Map<String, dynamic>.from(s)));
                } catch (_) {}
              }
              if (!_snapshotReady.isClosed) {
                _snapshotReady.add(null);
              }
            }
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    Future.delayed(const Duration(seconds: 5), () {
      if (!_disposed) _connect();
    });
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    if (!_snapshotReady.isClosed) {
      _snapshotReady.close();
    }
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

class LivePriceWebSocket {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _prices = <String, double>{};
  final _controller = StreamController<Map<String, double>>.broadcast();
  bool _disposed = false;

  Stream<Map<String, double>> get stream => _controller.stream;
  Map<String, double> get prices => Map.unmodifiable(_prices);

  void connect() {
    _connect();
  }

  void _connect() {
    if (_disposed) return;
    _subscription?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    final uri = Uri.parse('${AppConfig.wsBaseUrl}/live-candles');
    try {
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        (event) {
          if (_disposed || _controller.isClosed) return;
          try {
            final msg = jsonDecode(event as String) as Map<String, dynamic>;
            if (msg['type'] == 'candle' && msg['data'] != null) {
              final d = msg['data'] as Map<String, dynamic>;
              if (d['forming'] == true && d['interval'] == '5m') {
                final instrument = d['instrument'] as String?;
                final close = d['close'];
                if (instrument != null && close is num) {
                  _prices[instrument] = close.toDouble();
                  _controller.add(Map.from(_prices));
                }
              }
            } else if (msg['type'] == 'snapshot') {
              final candles = msg['candles'] as List<dynamic>? ?? [];
              for (final c in candles) {
                if (c is! Map) continue;
                final d = Map<String, dynamic>.from(c);
                if (d['interval'] == '5m' && d['forming'] == true) {
                  final instrument = d['instrument'] as String?;
                  final close = d['close'];
                  if (instrument != null && close is num) {
                    _prices[instrument] = close.toDouble();
                  }
                }
              }
              _controller.add(Map.from(_prices));
            }
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    Future.delayed(const Duration(seconds: 5), () {
      if (!_disposed) _connect();
    });
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}
