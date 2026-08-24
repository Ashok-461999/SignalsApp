import 'package:flutter_test/flutter_test.dart';
import 'package:signalapp_client/models/news_intel.dart';

void main() {
  test('MarketIntelResponse parses predictions and headlines', () {
    final data = MarketIntelResponse.fromJson({
      'predictions': [
        {
          'symbol': 'NIFTY',
          'name': 'Nifty 50',
          'type': 'index',
          'outlook': 'bullish',
          'confidence': 72,
          'headline_count': 3,
          'prediction': 'Bias up on headlines.',
          'option_hint': 'Prefer CE on dips',
        },
      ],
      'headlines': [
        {
          'source': 'ET',
          'title': 'Nifty rises on strong inflows',
          'sentiment': 'bullish',
          'score': 70,
          'symbols': ['NIFTY'],
          'prediction': 'Watch CE setups',
        },
      ],
      'disclaimer': 'Not advice',
    });

    expect(data.predictions, hasLength(1));
    expect(data.predictions.first.symbol, 'NIFTY');
    expect(data.predictions.first.optionHint, 'Prefer CE on dips');
    expect(data.headlines, hasLength(1));
    expect(data.headlines.first.symbols, ['NIFTY']);
    expect(data.disclaimer, 'Not advice');
  });

  test('MarketIntelResponse tolerates empty payload', () {
    final data = MarketIntelResponse.fromJson({});
    expect(data.predictions, isEmpty);
    expect(data.headlines, isEmpty);
    expect(data.disclaimer, '');
  });
}
