class Candle {
  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory Candle.fromJson(Map<String, dynamic> json) => Candle(
        timestamp: DateTime.parse(json['timestamp'] as String),
        open: (json['open'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        close: (json['close'] as num).toDouble(),
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
      );
}

class CandlesResponse {
  final String instrument;
  final String interval;
  final int count;
  final List<Candle> candles;

  const CandlesResponse({
    required this.instrument,
    required this.interval,
    required this.count,
    required this.candles,
  });

  factory CandlesResponse.fromJson(Map<String, dynamic> json) => CandlesResponse(
        instrument: json['instrument'] as String,
        interval: json['interval'] as String,
        count: json['count'] as int,
        candles: (json['candles'] as List<dynamic>)
            .map((e) => Candle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HealthResponse {
  final String status;
  final Map<String, dynamic> database;
  final Map<String, dynamic>? trading;
  final Map<String, dynamic>? crypto;

  const HealthResponse({
    required this.status,
    required this.database,
    this.trading,
    this.crypto,
  });

  factory HealthResponse.fromJson(Map<String, dynamic> json) => HealthResponse(
        status: json['status'] as String,
        database: Map<String, dynamic>.from(json['database'] as Map),
        trading: json['trading'] != null ? Map<String, dynamic>.from(json['trading'] as Map) : null,
        crypto: json['crypto'] != null ? Map<String, dynamic>.from(json['crypto'] as Map) : null,
      );
}
