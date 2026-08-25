import 'package:intl/intl.dart';

import 'market_session.dart';

class NewsHeadline {
  const NewsHeadline({
    required this.source,
    required this.title,
    this.sentiment = 'neutral',
    this.score = 50,
    this.symbols = const [],
    this.marketsAffected = const [],
    this.prediction = '',
    this.summary = '',
    this.category = 'indian',
    this.publishedAt = '',
    this.url = '',
  });

  final String source;
  final String title;
  final String sentiment;
  final int score;
  final List<String> symbols;
  final List<String> marketsAffected;
  final String prediction;
  final String summary;
  final String category;
  final String publishedAt;
  final String url;

  bool get isGlobal => category == 'global';
  bool get isIndian => category != 'global';

  DateTime? get publishedDateTime {
    if (publishedAt.isEmpty) return null;
    try {
      return DateTime.parse(publishedAt).toLocal();
    } catch (_) {
      return null;
    }
  }

  String get timeLabel {
    final dt = publishedDateTime;
    if (dt == null) return publishedAt.isNotEmpty ? publishedAt : '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return DateFormat('h:mm a').format(dt);
    if (diff.inDays < 7) return DateFormat('EEE h:mm a').format(dt);
    return DateFormat('d MMM, h:mm a').format(dt);
  }

  String get fullTimeLabel {
    final dt = publishedDateTime;
    if (dt == null) return publishedAt;
    return DateFormat('EEE, d MMM yyyy · h:mm a').format(dt);
  }

  List<String> get affectedMarkets =>
      marketsAffected.isNotEmpty ? marketsAffected : symbols;

  String get marketsLabel =>
      affectedMarkets.isEmpty ? 'Broad market' : affectedMarkets.join(', ');

  factory NewsHeadline.fromJson(Map<String, dynamic> json) => NewsHeadline(
        source: json['source'] as String? ?? '',
        title: json['title'] as String? ?? '',
        sentiment: json['sentiment'] as String? ?? 'neutral',
        score: (json['score'] as num?)?.toInt() ?? 50,
        symbols: (json['symbols'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        marketsAffected:
            (json['markets_affected'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        prediction: json['prediction'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        category: json['category'] as String? ?? 'indian',
        publishedAt: json['published_at'] as String? ?? '',
        url: json['url'] as String? ?? '',
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
    this.whyBullish = const [],
    this.whyBearish = const [],
    this.moveReason = '',
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
  final List<String> whyBullish;
  final List<String> whyBearish;
  final String moveReason;

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
        whyBullish: (json['why_bullish'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        whyBearish: (json['why_bearish'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        moveReason: json['move_reason'] as String? ?? '',
      );
}

class GiftNiftyInsight {
  const GiftNiftyInsight({
    this.available = false,
    this.lastPrice,
    this.changePoints,
    this.changePct,
    this.sessionClose = 'flat',
    this.predictedNiftyOpen = 'flat',
    this.negativeOpenProbability = 50,
    this.positiveOpenProbability = 50,
    this.preMarketWindow = false,
    this.summary = '',
    this.backtest = const {},
  });

  final bool available;
  final double? lastPrice;
  final double? changePoints;
  final double? changePct;
  final String sessionClose;
  final String predictedNiftyOpen;
  final int negativeOpenProbability;
  final int positiveOpenProbability;
  final bool preMarketWindow;
  final String summary;
  final Map<String, dynamic> backtest;

  factory GiftNiftyInsight.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return const GiftNiftyInsight();
    }
    final bt = json['backtest'];
    return GiftNiftyInsight(
      available: json['available'] as bool? ?? false,
      lastPrice: (json['last_price'] as num?)?.toDouble(),
      changePoints: (json['change_points'] as num?)?.toDouble(),
      changePct: (json['change_pct'] as num?)?.toDouble(),
      sessionClose: json['session_close'] as String? ?? 'flat',
      predictedNiftyOpen: json['predicted_nifty_open'] as String? ?? 'flat',
      negativeOpenProbability: (json['negative_open_probability'] as num?)?.toInt() ?? 50,
      positiveOpenProbability: (json['positive_open_probability'] as num?)?.toInt() ?? 50,
      preMarketWindow: json['pre_market_window'] as bool? ?? false,
      summary: json['summary'] as String? ?? '',
      backtest: bt is Map ? Map<String, dynamic>.from(bt) : const {},
    );
  }
}

class MarketIntelResponse {
  const MarketIntelResponse({
    required this.predictions,
    required this.headlines,
    this.disclaimer = '',
    this.giftNifty = const GiftNiftyInsight(),
    this.marketSession = const MarketSessionInfo(),
    this.traderBrief = const TraderBrief(),
  });

  final List<SymbolPrediction> predictions;
  final List<NewsHeadline> headlines;
  final String disclaimer;
  final GiftNiftyInsight giftNifty;
  final MarketSessionInfo marketSession;
  final TraderBrief traderBrief;

  factory MarketIntelResponse.fromJson(Map<String, dynamic> json) => MarketIntelResponse(
        predictions: (json['predictions'] as List<dynamic>? ?? [])
            .map((e) => SymbolPrediction.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        headlines: (json['headlines'] as List<dynamic>? ?? [])
            .map((e) => NewsHeadline.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        disclaimer: json['disclaimer'] as String? ?? '',
        giftNifty: GiftNiftyInsight.fromJson(
          json['gift_nifty'] is Map ? Map<String, dynamic>.from(json['gift_nifty'] as Map) : null,
        ),
        marketSession: MarketSessionInfo.fromJson(
          json['market_session'] is Map ? Map<String, dynamic>.from(json['market_session'] as Map) : null,
        ),
        traderBrief: TraderBrief.fromJson(
          json['trader_brief'] is Map ? Map<String, dynamic>.from(json['trader_brief'] as Map) : null,
        ),
      );
}
