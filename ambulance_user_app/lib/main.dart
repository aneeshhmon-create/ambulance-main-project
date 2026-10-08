import 'package:flutter/material.dart';

import 'config/routes.dart';
import 'models/user.dart';
import 'screens/home_screen.dart';
import 'screens/record_screen.dart';
import 'screens/register_screen.dart';
import 'screens/result_screen.dart';
import 'screens/submit_screen.dart';
import 'screens/tracking_placeholder_screen.dart';
import 'services/user_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AmbulanceUserApp());
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
        AppRoutes.tracking: (context) => const TrackingPlaceholderScreen(),
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
