import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalapp_client/models/candle.dart';
import 'package:signalapp_client/models/market_mode.dart';
import 'package:signalapp_client/models/models.dart';
import 'package:signalapp_client/models/news_intel.dart';
import 'package:signalapp_client/providers/app_providers.dart';
import 'package:signalapp_client/services/api_service.dart';

HealthResponse fakeHealth() => HealthResponse.fromJson({
      'status': 'ok',
      'database': {'ok': true},
      'smartapi': {'connected': true},
      'trading': {'paper_trading': true},
    });

class FakeSignalWebSocket extends SignalWebSocket {
  @override
  void connect() {}
}

class FakeLivePriceWebSocket extends LivePriceWebSocket {
  @override
  void connect() {}
}

List<Override> testShellOverrides({MarketIntelResponse? intel}) => [
      healthRefreshProvider.overrideWith((ref) {}),
      healthProvider.overrideWith((ref) async => fakeHealth()),
      marketIntelProvider.overrideWith(
        (ref) async => intel ?? const MarketIntelResponse(predictions: [], headlines: []),
      ),
      signalWsProvider.overrideWith((ref) {
        final ws = FakeSignalWebSocket();
        ref.onDispose(ws.dispose);
        return ws;
      }),
      livePriceWsProvider.overrideWith((ref) {
        final ws = FakeLivePriceWebSocket();
        ref.onDispose(ws.dispose);
        return ws;
      }),
      journalProvider.overrideWith((ref) async => {'entries': <dynamic>[]}),
      setupsProvider.overrideWith((ref) async => {'setups': <dynamic>[]}),
      tradingSettingsProvider.overrideWith((ref) async => Map<String, dynamic>.from(defaultTradingSettings)),
      regimesProvider.overrideWith((ref) async => {}),
      activeSignalsProvider.overrideWith((ref) => Stream.value(<SignalModel>[])),
      candlesProvider.overrideWith((ref, args) async {
        final (instrument, interval) = args;
        return CandlesResponse(instrument: instrument, interval: interval, count: 0, candles: const []);
      }),
    ];
