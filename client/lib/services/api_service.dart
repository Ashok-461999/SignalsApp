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

  // --- Crypto (keys stored on backend; Claude key stays on phone) ---

  Future<Map<String, dynamic>> getCryptoCredentialsStatus() async {
    final r = await _dio.get<Map<String, dynamic>>('/crypto/credentials');
    return r.data!;
  }

  Future<Map<String, dynamic>> saveCryptoCredentials({
    required String exchange,
    required String apiKey,
    required String apiSecret,
    String passphrase = '',
  }) async {
    final r = await _dio.put<Map<String, dynamic>>('/crypto/credentials', data: {
      'exchange': exchange,
      'api_key': apiKey,
      'api_secret': apiSecret,
      'passphrase': passphrase,
    });
    return r.data!;
  }

  Future<void> clearCryptoCredentials() async {
    await _dio.delete('/crypto/credentials');
  }

  Future<String> testCryptoCredentials({
    required String exchange,
    required String apiKey,
    required String apiSecret,
    String passphrase = '',
  }) async {
    final r = await _dio.post<Map<String, dynamic>>('/crypto/credentials/test', data: {
      'exchange': exchange,
      'api_key': apiKey,
      'api_secret': apiSecret,
      'passphrase': passphrase,
    });
    return r.data?['message'] as String? ?? 'Connected';
  }

  Future<List<Map<String, dynamic>>> getCryptoPrices() async {
    final r = await _dio.get<Map<String, dynamic>>('/crypto/prices');
    final prices = r.data?['prices'] as List<dynamic>? ?? [];
    return prices.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<CandlesResponse> getCryptoCandles({
    required String symbol,
    String interval = '5m',
    int limit = 120,
  }) async {
    final r = await _dio.get<Map<String, dynamic>>('/crypto/candles', queryParameters: {
      'symbol': symbol,
      'interval': interval,
      'limit': limit,
    });
    final raw = r.data?['candles'] as List<dynamic>? ?? [];
    final candles = raw
        .map((c) => Candle.fromJson({
              'timestamp': DateTime.fromMillisecondsSinceEpoch((c['timestamp'] as num).toInt()).toIso8601String(),
              'open': c['open'],
              'high': c['high'],
              'low': c['low'],
              'close': c['close'],
              'volume': c['volume'] ?? 0,
            }))
        .toList();
    return CandlesResponse(
      instrument: symbol,
      interval: interval,
      count: candles.length,
      candles: candles,
    );
  }

  Future<List<Map<String, dynamic>>> getCryptoBalances() async {
    final r = await _dio.get<Map<String, dynamic>>('/crypto/balances');
    final balances = r.data?['balances'] as List<dynamic>? ?? [];
    return balances.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getCryptoTrades({String symbol = 'BTC', int limit = 20}) async {
    final r = await _dio.get<Map<String, dynamic>>('/crypto/trades', queryParameters: {
      'symbol': symbol,
      'limit': limit,
    });
    final trades = r.data?['trades'] as List<dynamic>? ?? [];
    return trades.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> placeCryptoOrder({
    required String symbol,
    required String side,
    required double quantity,
    bool confirm = true,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>('/crypto/orders', data: {
      'symbol': symbol,
      'side': side,
      'quantity': quantity,
      'order_type': 'MARKET',
      'confirm': confirm,
    });
    return r.data!;
  }

  Future<Map<String, dynamic>> getTradingSettings() async {
    final r = await _dio.get<Map<String, dynamic>>('/settings/trading');
    return r.data!;
  }

  Future<Map<String, dynamic>> updateTradingSettings(Map<String, dynamic> data) async {
    final r = await _dio.patch<Map<String, dynamic>>('/settings/trading', data: data);
    return r.data!;
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
