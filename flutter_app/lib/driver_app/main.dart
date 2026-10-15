// lib/driver_app/main.dart
//
// Entry point for the Ambulance Driver App.
// Launch with:
//   flutter run --flavor driver -t lib/driver_app/main.dart
//   flutter build apk --flavor driver -t lib/driver_app/main.dart

import 'package:flutter/material.dart';
import 'package:ambulance_app/driver_app/screens/auth_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AmbulanceDriverApp());
}

class AmbulanceDriverApp extends StatelessWidget {
  const AmbulanceDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RapidAlert Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD32F2F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthPage(),
    );
  }
}
