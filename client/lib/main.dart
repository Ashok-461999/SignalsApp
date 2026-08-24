import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/news_intel_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signals_screen.dart';
import 'screens/watchlist_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_branding.dart';
import 'theme/app_theme.dart';
import 'widgets/app_background.dart';
import 'widgets/market_mode_switcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  await runZonedGuarded(() async {
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermission();
    runApp(const ProviderScope(child: AlphaPulseApp()));
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class AlphaPulseApp extends StatelessWidget {
  const AlphaPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBranding.name,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const MainShell(),
    );
  }
}

/// Backward compatibility alias.
typedef TradeMindApp = AlphaPulseApp;
typedef SignalApp = AlphaPulseApp;

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  final _screens = const [
    WatchlistScreen(),
    NewsIntelScreen(),
    SignalsScreen(),
    JournalScreen(),
    SettingsScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tradeAlertListenerProvider);
    ref.watch(healthRefreshProvider);

    return AppBackground(
      showImage: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            const MarketModeSwitcher(),
            Expanded(child: IndexedStack(index: _index, children: _screens)),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.surface.withValues(alpha: 0.98),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            ),
            child: NavigationBar(
              height: 64,
              backgroundColor: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: AppColors.accent.withValues(alpha: 0.14),
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              animationDuration: const Duration(milliseconds: 200),
              destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.candlestick_chart_outlined),
                    selectedIcon: Icon(Icons.candlestick_chart_rounded),
                    label: 'Markets',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.newspaper_outlined),
                    selectedIcon: Icon(Icons.newspaper_rounded),
                    label: 'Intel',
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
      ),
    );
  }
}
