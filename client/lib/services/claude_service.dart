import 'package:dio/dio.dart';

import '../models/models.dart';

/// Calls Anthropic Claude API from the user's device (API key stays on phone).
class ClaudeService {
  ClaudeService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.anthropic.com',
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 60),
                headers: {
                  'anthropic-version': '2023-06-01',
                  'content-type': 'application/json',
                },
              ),
            );

  final Dio _dio;

  Future<String> analyzeSignal({
    required String apiKey,
    required SignalModel signal,
    required List<Map<String, dynamic>> headlines,
  }) async {
    final newsBlock = headlines.isEmpty
        ? 'No headlines available.'
        : headlines.map((h) => '- ${h['title']} (${h['source']})').join('\n');

    final target = signal.underlyingTarget.isNotEmpty
        ? signal.underlyingTarget.map((t) => t.toStringAsFixed(1)).join(', ')
        : '—';

    final prompt = '''
You are an expert Indian index options trader (NIFTY, BANKNIFTY, SENSEX).
Analyze this automated signal and recent headlines. Be concise and practical.

SETUP
- Setup: ${signal.setupName}
- Instrument: ${signal.instrument}
- Direction: ${signal.direction}
- System decision: ${signal.tradeDecision}
- Regime: ${signal.regime} (${signal.strategyFit})
- Entry: ${signal.underlyingEntry.toStringAsFixed(1)} | SL: ${signal.underlyingStopLoss.toStringAsFixed(1)} | Targets: $target
- R:R: ${signal.riskReward.toStringAsFixed(2)} | IV percentile: ${signal.ivPercentile.toStringAsFixed(0)}%
- Strike/expiry: ${signal.suggestedStrike.toStringAsFixed(0)} / ${signal.suggestedExpiry}
- Rule engine reason: ${signal.decisionReason}

RECENT HEADLINES
$newsBlock

Respond in this exact format (keep total under 150 words):
VERDICT: AGREE | CAUTION | DISAGREE with the ${signal.tradeDecision} decision
NEWS: 1-2 sentences on how headlines affect this trade
RISK: biggest risk today for this setup
ACTION: what a disciplined trader should do

Not financial advice. No guarantee of profit.
''';

    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/messages',
      options: Options(headers: {'x-api-key': apiKey}),
      data: {
        'model': 'claude-3-5-haiku-20241022',
        'max_tokens': 400,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      },
    );

    final data = response.data;
    if (data == null) throw Exception('Empty response from Claude');

    final content = data['content'] as List<dynamic>? ?? [];
    for (final block in content) {
      final map = block as Map<String, dynamic>;
      if (map['type'] == 'text' && map['text'] != null) {
        return (map['text'] as String).trim();
      }
    }
    throw Exception('No text in Claude response');
  }

  Future<bool> testApiKey(String apiKey) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/messages',
      options: Options(headers: {'x-api-key': apiKey}),
      data: {
        'model': 'claude-3-5-haiku-20241022',
        'max_tokens': 16,
        'messages': [
          {'role': 'user', 'content': 'Reply with OK only.'},
        ],
      },
    );
    return response.statusCode == 200;
  }
}
