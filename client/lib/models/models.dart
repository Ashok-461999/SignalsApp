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
    required this.backtestStats,
    required this.timestamp,
    required this.tradable,
    this.tradeDecision = 'NO_TRADE',
    this.decisionReason = '',
    this.regime = '',
    this.strategyFit = '',
  });

  factory SignalModel.fromJson(Map<String, dynamic> json) => SignalModel(
        setupName: json['setup_name'] as String,
        instrument: json['instrument'] as String,
        segment: json['segment'] as String? ?? 'spot',
        direction: json['direction'] as String,
        underlyingEntry: (json['underlying_entry'] as num).toDouble(),
        underlyingStopLoss: (json['underlying_stop_loss'] as num).toDouble(),
        underlyingTarget: (json['underlying_target'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList(),
        suggestedStrike: (json['suggested_strike'] as num).toDouble(),
        suggestedExpiry: json['suggested_expiry'] as String,
        ivPercentile: (json['iv_percentile'] as num).toDouble(),
        riskReward: (json['risk_reward'] as num).toDouble(),
        positionSize: json['position_size'] as int,
        premiumStopReference: (json['premium_stop_reference'] as num).toDouble(),
        backtestStats: Map<String, dynamic>.from(json['backtest_stats'] as Map),
        timestamp: json['timestamp'] as String,
        tradable: json['tradable'] as bool? ?? true,
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
      );
}
