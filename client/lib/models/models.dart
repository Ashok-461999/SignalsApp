class SignalModel {
  final String setupName;
  final String instrument;
  final String segment;
  final String direction;
  final double underlyingEntry;
  final double underlyingStopLoss;
  final List<double> underlyingTarget;
  final double suggestedStrike;
  final String suggestedExpiry;
  final double ivPercentile;
  final double riskReward;
  final int positionSize;
  final double premiumStopReference;
  final double entryPremiumEstimate;
  final String optionType;
  final int daysToExpiry;
  final Map<String, dynamic> backtestStats;
  final String timestamp;
  final bool tradable;
  final String tradeDecision;
  final String decisionReason;
  final String regime;
  final String strategyFit;

  SignalModel({
    required this.setupName,
    required this.instrument,
    required this.segment,
    required this.direction,
    required this.underlyingEntry,
    required this.underlyingStopLoss,
    required this.underlyingTarget,
    required this.suggestedStrike,
    required this.suggestedExpiry,
    required this.ivPercentile,
    required this.riskReward,
    required this.positionSize,
    required this.premiumStopReference,
    this.entryPremiumEstimate = 0,
    this.optionType = '',
    this.daysToExpiry = 0,
    required this.backtestStats,
    required this.timestamp,
    required this.tradable,
    this.tradeDecision = 'NO_TRADE',
    this.decisionReason = '',
    this.regime = '',
    this.strategyFit = '',
  });

  String get optionLabel {
    if (optionType.isNotEmpty && suggestedStrike > 0) {
      return '${suggestedStrike.toStringAsFixed(0)} $optionType';
    }
    if (suggestedStrike > 0 && direction != 'neutral') {
      return '${suggestedStrike.toStringAsFixed(0)} ${direction == 'bullish' ? 'CE' : 'PE'}';
    }
    return '';
  }

  String get brokerOrderHint {
    if (tradeDecision != 'TAKE' || optionLabel.isEmpty) return '';
    return 'BUY $instrument $optionLabel × $positionSize lots';
  }

  /// LONG for bullish, SHORT for bearish (underlying bias).
  String get directionLabel {
    if (direction == 'bullish') return 'LONG';
    if (direction == 'bearish') return 'SHORT';
    return 'NEUTRAL';
  }

  /// Option action text shown on cards.
  String get actionLabel {
    if (optionLabel.isEmpty) return directionLabel == 'NEUTRAL' ? '' : directionLabel;
    return 'BUY $instrument $optionLabel';
  }

  /// Expected underlying move % to first target.
  double? get targetMovePercent {
    if (underlyingTarget.isEmpty || underlyingEntry <= 0) return null;
    final target = underlyingTarget.first;
    if (direction == 'bearish') {
      return ((underlyingEntry - target) / underlyingEntry) * 100;
    }
    return ((target - underlyingEntry) / underlyingEntry) * 100;
  }

  /// Historical setup win rate from backtest (0–100).
  double? get winRatePercent {
    final wr = backtestStats['win_rate'];
    if (wr is! num) return null;
    return wr <= 1 ? wr * 100 : wr.toDouble();
  }

  String get profitSummary {
    final parts = <String>[];
    final move = targetMovePercent;
    if (move != null && move > 0) {
      parts.add('${move >= 0 ? '+' : ''}${move.toStringAsFixed(2)}% target');
    }
    final wr = winRatePercent;
    if (wr != null && wr > 0) {
      parts.add('${wr.toStringAsFixed(0)}% win rate');
    }
    if (riskReward > 0) {
      parts.add('R:R ${riskReward.toStringAsFixed(1)}');
    }
    return parts.join(' · ');
  }

  String get expiryLabel {
    if (suggestedExpiry.isEmpty) return '';
    if (daysToExpiry > 0) return '$suggestedExpiry ($daysToExpiry DTE)';
    return suggestedExpiry;
  }

  int get signalAgeMinutes {
    if (timestamp.isEmpty) return 0;
    try {
      final ts = DateTime.parse(timestamp).toLocal();
      return DateTime.now().difference(ts).inMinutes;
    } catch (_) {
      return 0;
    }
  }

  bool get isStale => signalAgeMinutes > 10;

  String? get ivWarning =>
      ivPercentile >= 80 ? 'IV ${ivPercentile.toStringAsFixed(0)}% high — premium crush risk' : null;

  String? get dteWarning => daysToExpiry > 0 && daysToExpiry < 20
      ? 'Only $daysToExpiry DTE — prefer 20+ days for your style'
      : null;

  String? get freshnessLabel {
    if (timestamp.isEmpty) return null;
    if (signalAgeMinutes <= 5) return 'Fresh · $signalAgeMinutes min ago';
    if (signalAgeMinutes <= 15) return '$signalAgeMinutes min ago';
    return 'Stale · $signalAgeMinutes min ago — wait for new 5m bar';
  }

  static int _daysFromExpiryString(String expiry) {
    if (expiry.isEmpty) return 0;
    try {
      final d = DateTime.parse(expiry);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final exp = DateTime(d.year, d.month, d.day);
      return exp.difference(today).inDays;
    } catch (_) {
      return 0;
    }
  }

  static double _dbl(dynamic v, [double fallback = 0]) =>
      v is num ? v.toDouble() : fallback;

  static int _int(dynamic v, [int fallback = 0]) =>
      v is num ? v.toInt() : fallback;

  factory SignalModel.fromJson(Map<String, dynamic> json) => SignalModel(
        setupName: json['setup_name'] as String? ?? 'unknown',
        instrument: json['instrument'] as String? ?? '',
        segment: json['segment'] as String? ?? 'spot',
        direction: json['direction'] as String? ?? 'neutral',
        underlyingEntry: _dbl(json['underlying_entry']),
        underlyingStopLoss: _dbl(json['underlying_stop_loss']),
        underlyingTarget: (json['underlying_target'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        suggestedStrike: _dbl(json['suggested_strike']),
        suggestedExpiry: json['suggested_expiry'] as String? ?? '',
        ivPercentile: _dbl(json['iv_percentile']),
        riskReward: _dbl(json['risk_reward']),
        positionSize: _int(json['position_size']),
        premiumStopReference: _dbl(json['premium_stop_reference']),
        entryPremiumEstimate: _dbl(json['entry_premium_estimate']),
        optionType: json['option_type'] as String? ?? '',
        daysToExpiry: _int(json['days_to_expiry']) > 0
            ? _int(json['days_to_expiry'])
            : _daysFromExpiryString(json['suggested_expiry'] as String? ?? ''),
        backtestStats: json['backtest_stats'] is Map
            ? Map<String, dynamic>.from(json['backtest_stats'] as Map)
            : {},
        timestamp: json['timestamp'] as String? ?? '',
        tradable: json['tradable'] as bool? ?? false,
        tradeDecision: json['trade_decision'] as String? ?? 'NO_TRADE',
        decisionReason: json['decision_reason'] as String? ?? '',
        regime: json['regime'] as String? ?? '',
        strategyFit: json['strategy_fit'] as String? ?? '',
      );
}

class SetupSummary {
  final String setupName;
  final String instrument;
  final bool tradable;
  final Map<String, dynamic> stats;

  SetupSummary({
    required this.setupName,
    required this.instrument,
    required this.tradable,
    required this.stats,
  });

  factory SetupSummary.fromJson(Map<String, dynamic> json) => SetupSummary(
        setupName: json['setup_name'] as String,
        instrument: json['instrument'] as String,
        tradable: json['tradable'] as bool? ?? false,
        stats: Map<String, dynamic>.from(json['stats'] as Map? ?? {}),
      );
}

class JournalEntry {
  final int id;
  final String setupName;
  final String instrument;
  final String direction;
  final String status;
  final double underlyingEntry;
  final double underlyingStopLoss;
  final List<double> underlyingTarget;
  final double? suggestedStrike;
  final String? suggestedExpiry;
  final int plannedSize;
  final double? actualFillPrice;
  final double? exitPrice;
  final double? pnl;
  final String notes;
  final String? createdAt;

  JournalEntry({
    required this.id,
    required this.setupName,
    required this.instrument,
    required this.direction,
    required this.status,
    required this.underlyingEntry,
    required this.underlyingStopLoss,
    required this.underlyingTarget,
    this.suggestedStrike,
    this.suggestedExpiry,
    required this.plannedSize,
    this.actualFillPrice,
    this.exitPrice,
    this.pnl,
    required this.notes,
    this.createdAt,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: json['id'] as int,
        setupName: json['setup_name'] as String,
        instrument: json['instrument'] as String,
        direction: json['direction'] as String,
        status: json['status'] as String,
        underlyingEntry: (json['underlying_entry'] as num).toDouble(),
        underlyingStopLoss: (json['underlying_stop_loss'] as num).toDouble(),
        underlyingTarget: (json['underlying_target'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList(),
        suggestedStrike: (json['suggested_strike'] as num?)?.toDouble(),
        suggestedExpiry: json['suggested_expiry'] as String?,
        plannedSize: json['planned_size'] as int,
        actualFillPrice: (json['actual_fill_price'] as num?)?.toDouble(),
        exitPrice: (json['exit_price'] as num?)?.toDouble(),
        pnl: (json['pnl'] as num?)?.toDouble(),
        notes: json['notes'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );
}

class JournalSummary {
  final double totalPnl;
  final double todayPnl;
  final double weekPnl;
  final int closedTrades;
  final int openTrades;
  final int wins;
  final int losses;
  final double winRate;
  final double avgWin;
  final double avgLoss;
  final double largestWin;
  final double largestLoss;
  final double? profitFactor;
  final double expectancy;

  JournalSummary({
    required this.totalPnl,
    required this.todayPnl,
    required this.weekPnl,
    required this.closedTrades,
    required this.openTrades,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.avgWin,
    required this.avgLoss,
    required this.largestWin,
    required this.largestLoss,
    this.profitFactor,
    required this.expectancy,
  });

  factory JournalSummary.fromJson(Map<String, dynamic> json) => JournalSummary(
        totalPnl: (json['total_pnl'] as num?)?.toDouble() ?? 0,
        todayPnl: (json['today_pnl'] as num?)?.toDouble() ?? 0,
        weekPnl: (json['week_pnl'] as num?)?.toDouble() ?? 0,
        closedTrades: json['closed_trades'] as int? ?? 0,
        openTrades: json['open_trades'] as int? ?? 0,
        wins: json['wins'] as int? ?? 0,
        losses: json['losses'] as int? ?? 0,
        winRate: (json['win_rate'] as num?)?.toDouble() ?? 0,
        avgWin: (json['avg_win'] as num?)?.toDouble() ?? 0,
        avgLoss: (json['avg_loss'] as num?)?.toDouble() ?? 0,
        largestWin: (json['largest_win'] as num?)?.toDouble() ?? 0,
        largestLoss: (json['largest_loss'] as num?)?.toDouble() ?? 0,
        profitFactor: (json['profit_factor'] as num?)?.toDouble(),
        expectancy: (json['expectancy'] as num?)?.toDouble() ?? 0,
      );
}
