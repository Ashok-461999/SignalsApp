class NewsHeadline {
  const NewsHeadline({
    required this.source,
    required this.title,
    this.sentiment = 'neutral',
    this.score = 50,
    this.symbols = const [],
    this.prediction = '',
  });

  final String source;
  final String title;
  final String sentiment;
  final int score;
  final List<String> symbols;
  final String prediction;

  factory NewsHeadline.fromJson(Map<String, dynamic> json) => NewsHeadline(
        source: json['source'] as String? ?? '',
        title: json['title'] as String? ?? '',
        sentiment: json['sentiment'] as String? ?? 'neutral',
        score: (json['score'] as num?)?.toInt() ?? 50,
        symbols: (json['symbols'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        prediction: json['prediction'] as String? ?? '',
      );
}

class SymbolPrediction {
  const SymbolPrediction({
    required this.symbol,
    required this.name,
    required this.type,
    required this.outlook,
    required this.confidence,
    required this.headlineCount,
    required this.prediction,
    required this.optionHint,
    this.spotPrice,
    this.targetPrice,
    this.movePoints,
    this.moveDirection = 'flat',
    this.strategy = '',
    this.models = const [],
  });

  final String symbol;
  final String name;
  final String type;
  final String outlook;
  final int confidence;
  final int headlineCount;
  final String prediction;
  final String optionHint;
  final double? spotPrice;
  final double? targetPrice;
  final int? movePoints;
  final String moveDirection;
  final String strategy;
  final List<String> models;

  String get moveLabel {
    if (movePoints == null || movePoints! <= 0) return '';
    final sign = moveDirection == 'up' ? '+' : moveDirection == 'down' ? '-' : '±';
    return '$sign$movePoints pts';
  }

  factory SymbolPrediction.fromJson(Map<String, dynamic> json) => SymbolPrediction(
        symbol: json['symbol'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'stock',
        outlook: json['outlook'] as String? ?? 'neutral',
        confidence: (json['confidence'] as num?)?.toInt() ?? 50,
        headlineCount: (json['headline_count'] as num?)?.toInt() ?? 0,
        prediction: json['prediction'] as String? ?? '',
        optionHint: json['option_hint'] as String? ?? '',
        spotPrice: (json['spot_price'] as num?)?.toDouble(),
        targetPrice: (json['target_price'] as num?)?.toDouble(),
        movePoints: (json['move_points'] as num?)?.toInt(),
        moveDirection: json['move_direction'] as String? ?? 'flat',
        strategy: json['strategy'] as String? ?? '',
        models: (json['models'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      );
}

class MarketIntelResponse {
  const MarketIntelResponse({
    required this.predictions,
    required this.headlines,
    this.disclaimer = '',
  });

  final List<SymbolPrediction> predictions;
  final List<NewsHeadline> headlines;
  final String disclaimer;

  factory MarketIntelResponse.fromJson(Map<String, dynamic> json) => MarketIntelResponse(
        predictions: (json['predictions'] as List<dynamic>? ?? [])
            .map((e) => SymbolPrediction.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        headlines: (json['headlines'] as List<dynamic>? ?? [])
            .map((e) => NewsHeadline.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        disclaimer: json['disclaimer'] as String? ?? '',
      );
}
