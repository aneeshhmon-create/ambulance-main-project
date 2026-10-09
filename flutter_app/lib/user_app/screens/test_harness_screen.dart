// lib/user_app/screens/test_harness_screen.dart
//
// Standalone test entry point: lets you type an incident_id and navigate
// directly to the TrackingScreen without going through the submission flow.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tracking_screen.dart';

class TestHarnessScreen extends StatefulWidget {
  const TestHarnessScreen({super.key});

  @override
  State<TestHarnessScreen> createState() => _TestHarnessScreenState();
}

class _TestHarnessScreenState extends State<TestHarnessScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  void _navigate() {
    if (!_formKey.currentState!.validate()) return;
    final id = int.parse(_controller.text.trim());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TrackingScreen(incidentId: id)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking Screen — Test Harness'),
        backgroundColor: Colors.grey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter an Incident ID to open the tracking screen directly.\n'
                'Use this to test without going through the submission flow.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Incident ID',
                  hintText: 'e.g. 42',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an incident ID.';
                  }
                  final parsed = int.tryParse(value.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid positive integer.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _navigate(),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _navigate,
                icon: const Icon(Icons.track_changes),
                label: const Text('Open Tracking Screen'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
