// lib/user_app/main.dart
//
// Entry point for the Ambulance User App.
// Launch with:
//   flutter run  --flavor user -t lib/user_app/main.dart
//   flutter build apk --flavor user -t lib/user_app/main.dart

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ambulance_app/user_app/config/routes.dart';
import 'package:ambulance_app/user_app/models/user.dart';
import 'package:ambulance_app/user_app/screens/error_screen.dart';
import 'package:ambulance_app/user_app/screens/home_screen.dart';
import 'package:ambulance_app/user_app/screens/record_screen.dart';
import 'package:ambulance_app/user_app/screens/register_screen.dart';
import 'package:ambulance_app/user_app/screens/result_screen.dart';
import 'package:ambulance_app/user_app/screens/submit_screen.dart';
import 'package:ambulance_app/user_app/screens/tracking_screen.dart';
import 'package:ambulance_app/user_app/services/cleanup_service.dart';
import 'package:ambulance_app/user_app/services/user_storage.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Clean up stale report_*.m4a files (>24h old) in background
    unawaited(const CleanupService().cleanupStaleAudioFiles());

    // 2. Global framework error handler
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint(
        '>>> [FlutterError] Caught framework error: '
        '${details.exceptionAsString()}\n${details.stack}',
      );
    };

    // 3. Global friendly error page instead of red screen of death
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return GlobalErrorScreen(errorDetails: details);
    };

    runApp(const AmbulanceUserApp());
  }, (error, stack) {
    debugPrint('>>> [ZonedGuarded] Uncaught asynchronous error: $error\n$stack');
  });
}

/// Root widget for the Ambulance User App.
class AmbulanceUserApp extends StatelessWidget {
  const AmbulanceUserApp({super.key, this.userStorage});

  final UserStorage? userStorage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency Ambulance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: AppRoot(userStorage: userStorage),
      routes: {
        AppRoutes.register: (context) => const RegisterScreen(),
        AppRoutes.report: (context) => const RecordScreen(),
        AppRoutes.submit: (context) => const SubmitScreen(),
        AppRoutes.result: (context) => const ResultScreen(),
        AppRoutes.tracking: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final incidentId = args is int
              ? args
              : (args is String ? int.tryParse(args) ?? 0 : 0);
          return TrackingScreen(incidentId: incidentId);
        },
      },
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.root) {
          return MaterialPageRoute(
            builder: (context) => AppRoot(userStorage: userStorage),
          );
        }
        return null;
      },
    );
  }
}

/// Checks local user storage and renders either [HomeScreen] or [RegisterScreen].
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, this.userStorage});

  final UserStorage? userStorage;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final UserStorage _storage;
  bool _isChecking = true;
  User? _savedUser;

  @override
  void initState() {
    super.initState();
    _storage = widget.userStorage ?? UserStorage();
    _checkSavedUser();
  }

  Future<void> _checkSavedUser() async {
    final user = await _storage.loadUser();
    if (mounted) {
      setState(() {
        _savedUser = user;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_hospital_rounded,
                size: 72,
                color: Colors.red[700],
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Colors.red),
            ],
          ),
        ),
      );
    }

    if (_savedUser != null) {
      return HomeScreen(user: _savedUser);
    }

    return const RegisterScreen();
  }
}
