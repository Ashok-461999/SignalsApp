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
    expect(data.predictions.first.whyBullish, isEmpty);
    expect(data.predictions.first.moveReason, '');
    expect(data.headlines, hasLength(1));
    expect(data.headlines.first.symbols, ['NIFTY']);
    expect(data.disclaimer, 'Not advice');
  });

  test('MarketIntelResponse parses gift nifty block', () {
    final data = MarketIntelResponse.fromJson({
      'gift_nifty': {
        'available': true,
        'last_price': 24200.5,
        'change_pct': -0.35,
        'session_close': 'negative',
        'predicted_nifty_open': 'negative',
        'negative_open_probability': 78,
        'positive_open_probability': 22,
        'summary': 'GIFT negative — likely gap down',
      },
      'predictions': [],
      'headlines': [],
    });
    expect(data.giftNifty.available, isTrue);
    expect(data.giftNifty.negativeOpenProbability, 78);
    expect(data.giftNifty.predictedNiftyOpen, 'negative');
  });

  test('MarketIntelResponse tolerates empty payload', () {
    final data = MarketIntelResponse.fromJson({});
    expect(data.predictions, isEmpty);
    expect(data.headlines, isEmpty);
    expect(data.disclaimer, '');
  });
}
