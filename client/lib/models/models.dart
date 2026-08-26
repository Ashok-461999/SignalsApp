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
  final bool canTake;
  final int takeConfidence;
  final String tradingStyle;
  final String prediction;
  final double capitalInr;
  final double maxLossInr;
  final double premiumRequiredInr;
  final String holdHint;
  final String primaryLeg;
  final String dualLegNote;
  final String futuresAction;
  final int futuresLots;
  final double futuresMaxLossInr;
  final double futuresMarginInr;
  final double futuresMarginPerLotInr;
  final bool futuresCanTake;
  final String futuresReason;
  final String futuresBrokerHint;
  final int liveTrades;
  final int liveWins;
  final int liveLosses;
  final double liveWinRate;
  final double liveMaxDrawdownInr;
  final bool backtestProfitable;
  final String backtestVerdict;
  final String backtestSummary;
  final double backtestWinRate;
  final double backtestProfitFactor;
  final double backtestExpectancy;
  final double backtestMaxDrawdown;
  final int backtestTradeCount;

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
    this.canTake = false,
    this.takeConfidence = 0,
    this.tradingStyle = 'scalp',
    this.prediction = '',
    this.capitalInr = 0,
    this.maxLossInr = 0,
    this.premiumRequiredInr = 0,
    this.holdHint = '',
    this.primaryLeg = 'options',
    this.dualLegNote = '',
    this.futuresAction = '',
    this.futuresLots = 0,
    this.futuresMaxLossInr = 0,
    this.futuresMarginInr = 0,
    this.futuresMarginPerLotInr = 0,
    this.futuresCanTake = false,
    this.futuresReason = '',
    this.futuresBrokerHint = '',
    this.liveTrades = 0,
    this.liveWins = 0,
    this.liveLosses = 0,
    this.liveWinRate = 0,
    this.liveMaxDrawdownInr = 0,
    this.backtestProfitable = false,
    this.backtestVerdict = 'NO_DATA',
    this.backtestSummary = '',
    this.backtestWinRate = 0,
    this.backtestProfitFactor = 0,
    this.backtestExpectancy = 0,
    this.backtestMaxDrawdown = 0,
    this.backtestTradeCount = 0,
  });

  bool get backtestOk => backtestVerdict == 'PROFITABLE';
  bool get backtestFailed => backtestVerdict == 'NOT_PROFITABLE';

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

  String get futuresActionLabel {
    if (futuresAction.isNotEmpty) {
      return '$futuresAction $instrument FUT';
    }
    if (direction == 'bullish') return 'BUY $instrument FUT';
    if (direction == 'bearish') return 'SELL $instrument FUT';
    return '';
  }

  bool get hasFuturesLeg => futuresActionLabel.isNotEmpty && tradeDecision == 'TAKE';

  String get combinedBrokerHint {
    final parts = <String>[];
    if (brokerOrderHint.isNotEmpty) parts.add('OPTIONS: $brokerOrderHint');
    if (futuresBrokerHint.isNotEmpty) parts.add('FUTURES: $futuresBrokerHint');
    return parts.join('\n');
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
    if (backtestSummary.isNotEmpty) {
      parts.add(backtestSummary);
    } else if (wr != null && wr > 0) {
      parts.add('${wr.toStringAsFixed(0)}% backtest win');
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
        canTake: json['can_take'] as bool? ?? (json['trade_decision'] == 'TAKE'),
        takeConfidence: _int(json['take_confidence']),
        tradingStyle: json['trading_style'] as String? ?? 'scalp',
        prediction: json['prediction'] as String? ?? '',
        capitalInr: _dbl(json['capital_inr']),
        maxLossInr: _dbl(json['max_loss_inr']),
        premiumRequiredInr: _dbl(json['premium_required_inr']),
        holdHint: json['hold_hint'] as String? ?? '',
        primaryLeg: json['primary_leg'] as String? ?? 'options',
        dualLegNote: json['dual_leg_note'] as String? ?? '',
        futuresAction: json['futures_action'] as String? ?? '',
        futuresLots: _int(json['futures_lots']),
        futuresMaxLossInr: _dbl(json['futures_max_loss_inr']),
        futuresMarginInr: _dbl(json['futures_margin_inr']),
        futuresMarginPerLotInr: _dbl(json['futures_margin_per_lot_inr']),
        futuresCanTake: json['futures_can_take'] as bool? ?? false,
        futuresReason: json['futures_reason'] as String? ?? '',
        futuresBrokerHint: json['futures_broker_hint'] as String? ?? '',
        liveTrades: _liveInt(json, 'trades'),
        liveWins: _liveInt(json, 'wins'),
        liveLosses: _liveInt(json, 'losses'),
        liveWinRate: _liveDbl(json, 'win_rate'),
        liveMaxDrawdownInr: _liveDbl(json, 'max_drawdown_inr'),
        backtestProfitable: json['backtest_profitable'] as bool? ?? false,
        backtestVerdict: json['backtest_verdict'] as String? ?? 'NO_DATA',
        backtestSummary: json['backtest_summary'] as String? ?? '',
        backtestWinRate: _dbl(json['backtest_win_rate']),
        backtestProfitFactor: _dbl(json['backtest_profit_factor']),
        backtestExpectancy: _dbl(json['backtest_expectancy']),
        backtestMaxDrawdown: _dbl(json['backtest_max_drawdown']),
        backtestTradeCount: _int(json['backtest_trade_count']),
      );

  static int _liveInt(Map<String, dynamic> json, String key) {
    final live = json['live_track_record'];
    if (live is Map) return _int(live[key]);
    return 0;
  }

  static double _liveDbl(Map<String, dynamic> json, String key) {
    final live = json['live_track_record'];
    if (live is Map) return _dbl(live[key]);
    return 0;
  }
}

class TradeResult {
  const TradeResult({
    this.outcome = 'na',
    this.label = '',
    this.pnlValue,
    this.pnlPct,
    this.exitReason = '',
  });

  final String outcome;
  final String label;
  final double? pnlValue;
  final double? pnlPct;
  final String exitReason;

  bool get isProfit => outcome == 'profit';
  bool get isSlHit => outcome == 'sl_hit';
  bool get isOpen => outcome == 'open';

  factory TradeResult.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TradeResult();
    return TradeResult(
      outcome: json['outcome'] as String? ?? 'na',
      label: json['label'] as String? ?? '',
      pnlValue: (json['pnl_value'] as num?)?.toDouble(),
      pnlPct: (json['pnl_pct'] as num?)?.toDouble(),
      exitReason: json['exit_reason'] as String? ?? '',
    );
  }
}

class SignalHistoryItem {
  const SignalHistoryItem({
    required this.signal,
    required this.futuresResult,
    required this.optionsResult,
    this.logId = 0,
    this.loggedAt = '',
    this.optionsVerdict = '',
    this.futuresVerdict = '',
  });

  final SignalModel signal;
  final TradeResult futuresResult;
  final TradeResult optionsResult;
  final int logId;
  final String loggedAt;
  final String optionsVerdict;
  final String futuresVerdict;

  bool get optionsWon => optionsVerdict == 'WIN';
  bool get optionsFailed => optionsVerdict == 'FAIL';

  factory SignalHistoryItem.fromJson(Map<String, dynamic> json) => SignalHistoryItem(
        signal: SignalModel.fromJson(json),
        futuresResult: TradeResult.fromJson(
          json['futures_result'] is Map ? Map<String, dynamic>.from(json['futures_result'] as Map) : null,
        ),
        optionsResult: TradeResult.fromJson(
          json['options_result'] is Map ? Map<String, dynamic>.from(json['options_result'] as Map) : null,
        ),
        logId: (json['log_id'] as num?)?.toInt() ?? 0,
        loggedAt: json['logged_at'] as String? ?? json['timestamp'] as String? ?? '',
        optionsVerdict: json['options_verdict'] as String? ?? '',
        futuresVerdict: json['futures_verdict'] as String? ?? '',
      );
}

class SignalHistorySummary {
  const SignalHistorySummary({
    this.total = 0,
    this.resolvedTrades = 0,
    this.optionsProfit = 0,
    this.optionsSlHit = 0,
    this.optionsOpen = 0,
    this.futuresProfit = 0,
    this.futuresSlHit = 0,
    this.futuresOpen = 0,
    this.takeOptionsWinRate = 0,
    this.takeFuturesWinRate = 0,
    this.takeSignals = 0,
    this.takeOptionsWins = 0,
    this.takeOptionsFails = 0,
    this.takeOptionsOpen = 0,
    this.takeMaxDrawdownInr = 0,
    this.takeTotalPnlInr = 0,
    this.takeFuturesMaxDrawdownPts = 0,
  });

  final int total;
  final int resolvedTrades;
  final int optionsProfit;
  final int optionsSlHit;
  final int optionsOpen;
  final int futuresProfit;
  final int futuresSlHit;
  final int futuresOpen;
  final double takeOptionsWinRate;
  final double takeFuturesWinRate;
  final int takeSignals;
  final int takeOptionsWins;
  final int takeOptionsFails;
  final int takeOptionsOpen;
  final double takeMaxDrawdownInr;
  final double takeTotalPnlInr;
  final double takeFuturesMaxDrawdownPts;

  factory SignalHistorySummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SignalHistorySummary();
    return SignalHistorySummary(
      total: (json['total'] as num?)?.toInt() ?? 0,
      resolvedTrades: (json['resolved_trades'] as num?)?.toInt() ?? 0,
      optionsProfit: (json['options_profit'] as num?)?.toInt() ?? 0,
      optionsSlHit: (json['options_sl_hit'] as num?)?.toInt() ?? 0,
      optionsOpen: (json['options_open'] as num?)?.toInt() ?? 0,
      futuresProfit: (json['futures_profit'] as num?)?.toInt() ?? 0,
      futuresSlHit: (json['futures_sl_hit'] as num?)?.toInt() ?? 0,
      futuresOpen: (json['futures_open'] as num?)?.toInt() ?? 0,
      takeOptionsWinRate: (json['take_options_win_rate'] as num?)?.toDouble() ?? 0,
      takeFuturesWinRate: (json['take_futures_win_rate'] as num?)?.toDouble() ?? 0,
      takeSignals: (json['take_signals'] as num?)?.toInt() ?? 0,
      takeOptionsWins: (json['take_options_wins'] as num?)?.toInt() ?? 0,
      takeOptionsFails: (json['take_options_fails'] as num?)?.toInt() ?? 0,
      takeOptionsOpen: (json['take_options_open'] as num?)?.toInt() ?? 0,
      takeMaxDrawdownInr: (json['take_max_drawdown_inr'] as num?)?.toDouble() ?? 0,
      takeTotalPnlInr: (json['take_total_pnl_inr'] as num?)?.toDouble() ?? 0,
      takeFuturesMaxDrawdownPts: (json['take_futures_max_drawdown_pts'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SignalHistoryResponse {
  const SignalHistoryResponse({
    required this.items,
    required this.summary,
    this.livePerformance = const {},
  });

  final List<SignalHistoryItem> items;
  final SignalHistorySummary summary;
  final Map<String, dynamic> livePerformance;

  factory SignalHistoryResponse.fromJson(Map<String, dynamic> json) => SignalHistoryResponse(
        items: (json['signals'] as List<dynamic>? ?? [])
            .map((e) => SignalHistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        summary: SignalHistorySummary.fromJson(
          json['summary'] is Map ? Map<String, dynamic>.from(json['summary'] as Map) : null,
        ),
        livePerformance: json['live_performance'] is Map
            ? Map<String, dynamic>.from(json['live_performance'] as Map)
            : const {},
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
