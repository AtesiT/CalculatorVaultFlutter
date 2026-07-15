import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'calculator_screen.dart';
import 'vault_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Handled Flutter error: ${details.exceptionAsString()}');
    };

    await Hive.initFlutter();
    await VaultService.instance.init();

    runApp(const CalculatorVaultApp());
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
  });
}

class CalculatorVaultApp extends StatefulWidget {
  const CalculatorVaultApp({super.key});

  @override
  State<CalculatorVaultApp> createState() => _CalculatorVaultAppState();
}

class _CalculatorVaultAppState extends State<CalculatorVaultApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _lockVaultIfOpen();
    }
  }

  void _lockVaultIfOpen() {
    if (!VaultService.instance.isVaultOpen) return;
    VaultService.instance.isVaultOpen = false;
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const CalculatorScreen(),
    );
  }
}