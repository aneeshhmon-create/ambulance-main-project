import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/user_storage.dart';

/// Home screen — main patient dashboard.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.user,
    this.apiService,
    this.userStorage,
  });

  final User? user;
  final ApiService? apiService;
  final UserStorage? userStorage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiService _api;
  late final UserStorage _storage;

  User? _currentUser;
  bool _isLoadingUser = true;

  // Tri-state for Developer connection check widget
  _ConnectionState _connectionState = _ConnectionState.idle;
  String _connectionMessage = '';

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
    _storage = widget.userStorage ?? UserStorage();
    _initUser();
  }

  Future<void> _initUser() async {
    if (widget.user != null) {
      setState(() {
        _currentUser = widget.user;
        _isLoadingUser = false;
      });
      return;
    }

    final loaded = await _storage.loadUser();
    if (mounted) {
      setState(() {
        _currentUser = loaded;
        _isLoadingUser = false;
      });
    }
  }

  Future<void> _switchUser() async {
    await _storage.clearUser();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/register', (route) => false);
  }

  Future<void> _testConnection() async {
    setState(() {
      _connectionState = _ConnectionState.loading;
      _connectionMessage = '';
    });

    try {
      final result = await _api.checkHealth();
      if (mounted) {
        setState(() {
          _connectionState = _ConnectionState.success;
          _connectionMessage = result.toString();
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _connectionState = _ConnectionState.failure;
          _connectionMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectionState = _ConnectionState.failure;
          _connectionMessage = 'An unexpected error occurred. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final displayName = _currentUser?.name ?? 'User';
    final displayPhone = _currentUser?.phone ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Ambulance'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Greeting section
              Text(
                'Hi, $displayName',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
              if (displayPhone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Mobile: $displayPhone',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                ),
              ],
              const SizedBox(height: 32),

              // Large Red "Report Emergency" button
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.emergency_share_rounded,
                        color: Colors.red,
                        size: 72,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Need Immediate Assistance?',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Dispatch an ambulance and find nearest hospital bed allocation with one tap.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/report');
                          },
                          icon: const Icon(Icons.warning_amber_rounded, size: 28),
                          label: const Text(
                            'Report Emergency',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Switch user button
              Center(
                child: TextButton.icon(
                  onPressed: _switchUser,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Switch user'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Collapsed Developer section
              ExpansionTile(
                title: Text(
                  'Developer Options (Backend Check)',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                tilePadding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Backend: ${ApiConfig.baseUrl}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _connectionState == _ConnectionState.loading
                              ? null
                              : _testConnection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Test Connection'),
                        ),
                        const SizedBox(height: 16),
                        _buildStatusWidget(),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusWidget() {
    switch (_connectionState) {
      case _ConnectionState.idle:
        return const SizedBox.shrink();

      case _ConnectionState.loading:
        return const Center(child: CircularProgressIndicator());

      case _ConnectionState.success:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            border: Border.all(color: Colors.green),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(height: 4),
              const Text(
                'Connected',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _connectionMessage,
                style: const TextStyle(color: Colors.black87, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

      case _ConnectionState.failure:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red[50],
            border: Border.all(color: Colors.red),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 28),
              const SizedBox(height: 4),
              Text(
                _connectionMessage,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _testConnection,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
    }
  }
}

enum _ConnectionState { idle, loading, success, failure }
