import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/journal_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signals_screen.dart';
import 'screens/watchlist_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/market_mode_switcher.dart';

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
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
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
    ref.watch(tradeAlertListenerProvider);

    return Scaffold(
      body: Column(
        children: [
          const MarketModeSwitcher(),
          Expanded(child: IndexedStack(index: _index, children: _screens)),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: NavigationBar(
            height: 68,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.candlestick_chart_outlined),
                selectedIcon: Icon(Icons.candlestick_chart_rounded),
                label: 'Markets',
              ),
              NavigationDestination(
                icon: Icon(Icons.bolt_outlined),
                selectedIcon: Icon(Icons.bolt_rounded),
                label: 'Signals',
              ),
              NavigationDestination(
                icon: Icon(Icons.wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'P&L',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
