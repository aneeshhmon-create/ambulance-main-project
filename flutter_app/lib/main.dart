// lib/main.dart
//
// Entry point for the ambulance patient app.
// During development the app launches the TestHarnessScreen so you can
// jump straight to any incident. Swap home: to your real home screen
// once the full submission flow is built.

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
      title: 'Ambulance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(elevation: 2),
      ),
      // ── Swap this home: once the submission flow is ready ──────────────────
      home: const TestHarnessScreen(),
    );
  }
}