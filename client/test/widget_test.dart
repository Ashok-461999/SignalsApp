import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:signalapp_client/main.dart';
import 'package:signalapp_client/models/news_intel.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('App loads main shell with navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testShellOverrides(),
        child: const AlphaPulseApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Markets'), findsOneWidget);
    expect(find.text('Intel'), findsOneWidget);
    expect(find.text('Signals'), findsOneWidget);
  });

  testWidgets('Intel tab shows scrollable market intel', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testShellOverrides(
          intel: const MarketIntelResponse(
            predictions: [
              SymbolPrediction(
        symbol: 'NIFTY',
        name: 'Nifty 50',
        type: 'index',
        outlook: 'bullish',
        confidence: 70,
        headlineCount: 2,
        prediction: 'Up bias',
        optionHint: 'CE on dips',
        movePoints: 100,
        moveDirection: 'up',
        spotPrice: 25000,
        targetPrice: 25100,
        strategy: 'ORB breakout',
        models: ['ORB breakout', 'News momentum'],
              ),
            ],
            headlines: [
              NewsHeadline(source: 'ET', title: 'Markets rise', sentiment: 'bullish'),
            ],
            disclaimer: 'Test',
          ),
        ),
        child: const AlphaPulseApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Intel'));
    await tester.pumpAndSettle();

    expect(find.text('Market intel'), findsOneWidget);
    expect(find.text('NIFTY'), findsOneWidget);
    expect(find.text('+100 pts'), findsOneWidget);
    expect(find.text('ORB breakout'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pump();
  });
}
