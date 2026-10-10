// lib/ambulance_app/main.dart
//
// Entry point for the Ambulance Driver App.
// Launch with: flutter run -t lib/ambulance_app/main.dart

import 'package:flutter/material.dart';
import 'screens/driver_location_screen.dart';

void main() {
  runApp(const AmbulanceDriverApp());
}

class AmbulanceDriverApp extends StatelessWidget {
  const AmbulanceDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ambulance Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DriverLocationScreen(),
    );
  }
}
