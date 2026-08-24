class MarketSessionInfo {
  const MarketSessionInfo({
    this.istTime = '',
    this.phase = 'market_closed',
    this.phaseLabel = '',
    this.isTradingDay = true,
    this.marketHours = '09:15 – 15:30 IST',
    this.nextBarAt = '',
    this.minutesToNextBar,
    this.signalsActive = false,
    this.fiiDii,
    this.traderTips = const [],
  });

  final String istTime;
  final String phase;
  final String phaseLabel;
  final bool isTradingDay;
  final String marketHours;
  final String nextBarAt;
  final int? minutesToNextBar;
  final bool signalsActive;
  final FiiDiiFlow? fiiDii;
  final List<String> traderTips;

  factory MarketSessionInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const MarketSessionInfo();
    final fii = json['fii_dii'];
    return MarketSessionInfo(
      istTime: json['ist_time'] as String? ?? '',
      phase: json['phase'] as String? ?? 'market_closed',
      phaseLabel: json['phase_label'] as String? ?? '',
      isTradingDay: json['is_trading_day'] as bool? ?? true,
      marketHours: json['market_hours'] as String? ?? '09:15 – 15:30 IST',
      nextBarAt: json['next_bar_at'] as String? ?? '',
      minutesToNextBar: (json['minutes_to_next_bar'] as num?)?.toInt(),
      signalsActive: json['signals_active'] as bool? ?? false,
      fiiDii: fii is Map ? FiiDiiFlow.fromJson(Map<String, dynamic>.from(fii)) : null,
      traderTips: (json['trader_tips'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
    );
  }
}

class FiiDiiFlow {
  const FiiDiiFlow({this.date = '', this.fiiNetCr = 0, this.diiNetCr = 0, this.summary = ''});
  final String date;
  final double fiiNetCr;
  final double diiNetCr;
  final String summary;

  factory FiiDiiFlow.fromJson(Map<String, dynamic> json) => FiiDiiFlow(
        date: json['date'] as String? ?? '',
        fiiNetCr: (json['fii_net_cr'] as num?)?.toDouble() ?? 0,
        diiNetCr: (json['dii_net_cr'] as num?)?.toDouble() ?? 0,
        summary: json['summary'] as String? ?? '',
      );
}

class TraderBrief {
  const TraderBrief({
    this.headline = '',
    this.painPoints = const [],
    this.actionItems = const [],
    this.session = const MarketSessionInfo(),
  });

  final String headline;
  final List<String> painPoints;
  final List<String> actionItems;
  final MarketSessionInfo session;

  factory TraderBrief.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const TraderBrief();
    return TraderBrief(
      headline: json['headline'] as String? ?? '',
      painPoints: (json['pain_points'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      actionItems: (json['action_items'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      session: MarketSessionInfo.fromJson(
        json['session'] is Map ? Map<String, dynamic>.from(json['session'] as Map) : null,
      ),
    );
  }
}
