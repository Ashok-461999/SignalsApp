import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../models/candle.dart';
import '../models/models.dart';

class ApiService {
  ApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ));

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
}

class SignalWebSocket {
  WebSocketChannel? _channel;
  final _controller = StreamController<SignalModel>.broadcast();

  Stream<SignalModel> get stream => _controller.stream;

  void connect() {
    final uri = Uri.parse('${AppConfig.wsBaseUrl}/signals');
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen((event) {
      final msg = jsonDecode(event as String) as Map<String, dynamic>;
      if (msg['type'] == 'signal' && msg['data'] != null) {
        _controller.add(SignalModel.fromJson(msg['data'] as Map<String, dynamic>));
      } else if (msg['type'] == 'snapshot' && msg['signals'] != null) {
        for (final s in msg['signals'] as List<dynamic>) {
          _controller.add(SignalModel.fromJson(s as Map<String, dynamic>));
        }
      }
    });
  }

  void dispose() {
    _channel?.sink.close();
    _controller.close();
  }
}

class LivePriceWebSocket {
  WebSocketChannel? _channel;
  final _prices = <String, double>{};
  final _controller = StreamController<Map<String, double>>.broadcast();

  Stream<Map<String, double>> get stream => _controller.stream;
  Map<String, double> get prices => Map.unmodifiable(_prices);

  void connect() {
    final uri = Uri.parse('${AppConfig.wsBaseUrl}/live-candles');
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen((event) {
      final msg = jsonDecode(event as String) as Map<String, dynamic>;
      if (msg['type'] == 'candle' && msg['data'] != null) {
        final d = msg['data'] as Map<String, dynamic>;
        if (d['forming'] == true && d['interval'] == '5m') {
          _prices[d['instrument'] as String] = (d['close'] as num).toDouble();
          _controller.add(Map.from(_prices));
        }
      } else if (msg['type'] == 'snapshot' && msg['candles'] != null) {
        for (final c in msg['candles'] as List<dynamic>) {
          final d = c as Map<String, dynamic>;
          if (d['interval'] == '5m' && d['forming'] == true) {
            _prices[d['instrument'] as String] = (d['close'] as num).toDouble();
          }
        }
        _controller.add(Map.from(_prices));
      }
    });
  }

  void dispose() {
    _channel?.sink.close();
    _controller.close();
  }
}
