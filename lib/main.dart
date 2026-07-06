import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'calculator_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const CalculatorVaultApp());
}

class CalculatorVaultApp extends StatelessWidget {
  const CalculatorVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const CalculatorScreen(),
    );
  }
}