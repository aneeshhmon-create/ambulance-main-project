import 'package:flutter/material.dart';

import 'models/incident.dart';
import 'models/user.dart';
import 'screens/home_screen.dart';
import 'screens/record_screen.dart';
import 'screens/register_screen.dart';
import 'screens/submit_screen.dart';
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
        '/register': (context) => const RegisterScreen(),
        '/report': (context) => const RecordScreen(),
        '/submit': (context) => const SubmitScreen(),
        '/result': (context) => const ResultPlaceholderScreen(),
        // Shared-friendly routes for Person C:
        // '/tracking': (context) => const TrackingScreen(),
        // '/driver_location': (context) => const DriverLocationScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
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

/// Placeholder screen for Day 5 polished result & tracking UI.
///
/// Displays the parsed response summary as plain text.
class ResultPlaceholderScreen extends StatelessWidget {
  const ResultPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final incident =
        ModalRoute.of(context)?.settings.arguments as Incident?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch Summary'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: incident == null
              ? const Center(child: Text('No incident data received.'))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Incident #${incident.id} created (${incident.status})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Voice Transcript:',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        incident.transcript?.isNotEmpty == true
                            ? incident.transcript!
                            : '(no transcript available)',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                      const Divider(height: 32),
                      _buildInfoRow('Emergency Type', incident.emergencyType ?? 'unspecified'),
                      _buildInfoRow('Severity', incident.severity ?? 'unspecified'),
                      _buildInfoRow('Department Needed', incident.departmentNeeded ?? 'General Medicine'),
                      _buildInfoRow('Victims', '${incident.victims}'),
                      _buildInfoRow('Symptoms', incident.symptoms.isNotEmpty ? incident.symptoms.join(', ') : 'None listed'),
                      _buildInfoRow('Hospitals Broadcast', '${incident.broadcasts.length} nearby hospitals'),
                      if (incident.assignedAmbulance != null)
                        _buildInfoRow(
                          'Assigned Ambulance',
                          '${incident.assignedAmbulance!.driverName} (${incident.assignedAmbulance!.driverPhone})',
                        ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                          },
                          child: const Text('Back to Home'),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
