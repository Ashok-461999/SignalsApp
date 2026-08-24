import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalapp_client/models/candle.dart';
import 'package:signalapp_client/widgets/candlestick_chart.dart';

List<Candle> _sampleCandles() => List.generate(
      20,
      (i) => Candle(
        timestamp: DateTime(2026, 1, 1, 9, 15 + i),
        open: 100.0 + i,
        high: 102.0 + i,
        low: 99.0 + i,
        close: 101.0 + i,
        volume: 1000.0 + i * 10,
      ),
    );

void main() {
  testWidgets('CandlestickChart renders without overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              CandlestickChart(candles: _sampleCandles(), height: 320, showVolume: true),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Pinch to zoom · scroll page to move'), findsOneWidget);
  });

  testWidgets('CandlestickChart handles empty candles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CandlestickChart(candles: [], height: 200),
        ),
      ),
    );
    expect(find.text('No candle data'), findsOneWidget);
  });
}
