import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/journal_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signals_screen.dart';
import 'screens/watchlist_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();
  runApp(const ProviderScope(child: SignalApp()));
}

class SignalApp extends StatelessWidget {
  const SignalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SignalApp',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo), useMaterial3: true),
      home: const MainShell(),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  final _screens = const [
    WatchlistScreen(),
    SignalsScreen(),
    JournalScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Keep trade alert listener alive for background notifications
    ref.watch(tradeAlertListenerProvider);

    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'Watchlist'),
          NavigationDestination(icon: Icon(Icons.bolt), label: 'Signals'),
          NavigationDestination(icon: Icon(Icons.book), label: 'Journal'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
