import 'package:flutter/material.dart';

/// Placeholder screen for Person C's tracking feature.
///
/// Route: `/tracking`
/// Argument: incident ID as [int]
class TrackingPlaceholderScreen extends StatelessWidget {
  const TrackingPlaceholderScreen({super.key, this.incidentId});

  final int? incidentId;

  @override
  Widget build(BuildContext context) {
    final routeArg = ModalRoute.of(context)?.settings.arguments;
    final id = incidentId ?? (routeArg is int ? routeArg : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.navigation_rounded, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Tracking screen - owned by Person C',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                id != null ? 'Incident ID: #$id' : 'No incident ID provided',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
