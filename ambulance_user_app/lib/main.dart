import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

/// Entry point for the Ambulance User App.
///
/// Defines named routes so multiple teammates can add screens
/// without touching each other's files:
///   '/'                → HomeScreen              (Person B — Day 1)
///   '/tracking'        → TrackingScreen          (Person C — upcoming)
///   '/driver_location' → DriverLocationScreen    (Person C — upcoming)
void main() {
  runApp(const AmbulanceUserApp());
}

class AmbulanceUserApp extends StatelessWidget {
  const AmbulanceUserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency Ambulance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      // Named route table — Person C adds entries here for their screens.
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        // '/tracking': (context) => const TrackingScreen(),
        // '/driver_location': (context) => const DriverLocationScreen(),
      },
    );
  }
}
