
import 'package:flutter/material.dart';
import 'screens/test_harness_screen.dart';

void main() {
  runApp(const AmbulanceApp());
}

class AmbulanceApp extends StatelessWidget {
  const AmbulanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ambulance App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(elevation: 2),
      ),
      home: const TestHarnessScreen(),
    );
  }
}
