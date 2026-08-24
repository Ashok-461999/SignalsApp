enum MarketMode {
  indian,
  crypto;

  String get label => switch (this) {
        MarketMode.indian => 'Indian Market',
        MarketMode.crypto => 'Crypto',
      };

  String get shortLabel => switch (this) {
        MarketMode.indian => 'India',
        MarketMode.crypto => 'Crypto',
      };

  static MarketMode fromString(String? value) {
    if (value == 'crypto') return MarketMode.crypto;
    return MarketMode.indian;
  }

  String get storageValue => name;
}

/// Crypto pairs — backend integration coming soon.
class CryptoInstrument {
  const CryptoInstrument({
    required this.symbol,
    required this.name,
    required this.quote,
  });

  final String symbol;
  final String name;
  final String quote;
}

const cryptoWatchlist = [
  CryptoInstrument(symbol: 'BTC', name: 'Bitcoin', quote: 'USDT'),
  CryptoInstrument(symbol: 'ETH', name: 'Ethereum', quote: 'USDT'),
  CryptoInstrument(symbol: 'SOL', name: 'Solana', quote: 'USDT'),
  CryptoInstrument(symbol: 'BNB', name: 'BNB', quote: 'USDT'),
];

const indianIndices = ['NIFTY', 'BANKNIFTY', 'SENSEX'];

/// Liquid NSE F&O stocks — news predictions & options context.
class FnoStock {
  const FnoStock({required this.symbol, required this.name});
  final String symbol;
  final String name;
}

const indianFnoStocks = [
  FnoStock(symbol: 'RELIANCE', name: 'Reliance'),
  FnoStock(symbol: 'TCS', name: 'TCS'),
  FnoStock(symbol: 'HDFCBANK', name: 'HDFC Bank'),
  FnoStock(symbol: 'INFY', name: 'Infosys'),
  FnoStock(symbol: 'ICICIBANK', name: 'ICICI Bank'),
  FnoStock(symbol: 'SBIN', name: 'SBI'),
  FnoStock(symbol: 'BHARTIARTL', name: 'Airtel'),
  FnoStock(symbol: 'ITC', name: 'ITC'),
  FnoStock(symbol: 'KOTAKBANK', name: 'Kotak Bank'),
  FnoStock(symbol: 'LT', name: 'L&T'),
  FnoStock(symbol: 'AXISBANK', name: 'Axis Bank'),
  FnoStock(symbol: 'TATAMOTORS', name: 'Tata Motors'),
];

enum CryptoExchange {
  binance,
  bybit,
  coindcx;

  String get label => switch (this) {
        CryptoExchange.binance => 'Binance',
        CryptoExchange.bybit => 'Bybit',
        CryptoExchange.coindcx => 'CoinDCX (India)',
      };

  static CryptoExchange fromString(String? value) => switch (value) {
        'bybit' => CryptoExchange.bybit,
        'coindcx' => CryptoExchange.coindcx,
        _ => CryptoExchange.binance,
      };
}

class CryptoCredentials {
  const CryptoCredentials({
    required this.exchange,
    required this.apiKey,
    required this.apiSecret,
    this.passphrase = '',
  });

  final CryptoExchange exchange;
  final String apiKey;
  final String apiSecret;
  final String passphrase;

  bool get isConfigured => apiKey.isNotEmpty && apiSecret.isNotEmpty;
}

/// Status from backend — secrets never sent to the phone.
class CryptoCredentialsStatus {
  const CryptoCredentialsStatus({
    required this.configured,
    required this.exchange,
    this.apiKeyHint,
  });

  final bool configured;
  final CryptoExchange exchange;
  final String? apiKeyHint;

  factory CryptoCredentialsStatus.fromJson(Map<String, dynamic> json) {
    return CryptoCredentialsStatus(
      configured: json['configured'] as bool? ?? false,
      exchange: CryptoExchange.fromString(json['exchange'] as String?),
      apiKeyHint: json['api_key_hint'] as String?,
    );
  }
}
