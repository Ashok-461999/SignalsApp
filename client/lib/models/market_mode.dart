const indianIndices = ['NIFTY', 'BANKNIFTY', 'FINNIFTY', 'SENSEX'];

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
