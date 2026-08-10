import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:signalapp_client/main.dart';

void main() {
  testWidgets('App loads main shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SignalApp()));
    expect(find.text('Watchlist'), findsOneWidget);
  });
}
