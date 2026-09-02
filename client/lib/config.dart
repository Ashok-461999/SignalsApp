import 'dart:io';

class AppConfig {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const String _envWsUrl = String.fromEnvironment('WS_BASE_URL', defaultValue: '');

  static String get apiBaseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    // AWS EC2 Mumbai — My Indian Market (t3.micro ap-south-1)
    if (Platform.isAndroid) return 'http://13.235.102.43';
    return 'http://localhost:8000';
  }

  static String get wsBaseUrl {
    if (_envWsUrl.isNotEmpty) return _envWsUrl;
    final base = apiBaseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    return base;
  }
}
