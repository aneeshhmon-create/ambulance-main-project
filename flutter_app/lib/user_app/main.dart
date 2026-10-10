// lib/user_app/main.dart
//
// Entry point for the User App.
// Launch with: flutter run -t lib/user_app/main.dart

import 'package:flutter/material.dart';
import 'screens/test_harness_screen.dart';

void main() {
  runApp(const UserApp());
}

class UserApp extends StatelessWidget {
  const UserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ambulance Tracker',
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
