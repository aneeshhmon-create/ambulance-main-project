import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';

/// Home screen — entry point of the patient-facing UI.
///
/// Responsibilities (Day 1):
///   - Display the configured backend URL so the user can verify connectivity.
///   - Provide a "Test Connection" button that calls GET /health.
///   - Show a spinner while the request is in flight.
///   - Show a green "Connected" banner with the raw response on success.
///   - Show a red error message with a "Retry" button on any failure.
///   - Never crash regardless of network state.
///
/// Screens to be added by Person C (same named-route map):
///   /tracking        → lib/screens/tracking_screen.dart
///   /driver_location → lib/screens/driver_location_screen.dart
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();

  /// Tri-state for the connection check result.
  _ConnectionState _state = _ConnectionState.idle;
  String _message = '';

  Future<void> _testConnection() async {
    setState(() {
      _state = _ConnectionState.loading;
      _message = '';
    });

    try {
      final result = await _api.checkHealth();
      setState(() {
        _state = _ConnectionState.success;
        _message = result.toString();
      });
    } on ApiException catch (e) {
      setState(() {
        _state = _ConnectionState.failure;
        _message = e.message;
      });
    } catch (e) {
      // Safety net: should never reach here, but we must never crash.
      setState(() {
        _state = _ConnectionState.failure;
        _message = 'An unexpected error occurred. Please retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Ambulance'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backend URL indicator
            Text(
              'Backend: ${ApiConfig.baseUrl}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Action button
            ElevatedButton(
              onPressed:
                  _state == _ConnectionState.loading ? null : _testConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
              child: const Text('Test Connection'),
            ),
            const SizedBox(height: 32),

            // Status area
            _buildStatusWidget(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusWidget() {
    switch (_state) {
      case _ConnectionState.idle:
        return const SizedBox.shrink();

      case _ConnectionState.loading:
        return const Center(child: CircularProgressIndicator());

      case _ConnectionState.success:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green[50],
            border: Border.all(color: Colors.green),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(height: 8),
              const Text(
                'Connected',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _message,
                style: const TextStyle(color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

      case _ConnectionState.failure:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red[50],
            border: Border.all(color: Colors.red),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                _message,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
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
