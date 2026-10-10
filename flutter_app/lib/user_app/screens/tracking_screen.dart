// lib/user_app/screens/tracking_screen.dart
//
// Live incident tracking screen.
// Polls GET /incidents/{incident_id} every 3 seconds and renders a visual
// status progression. Stops polling when status reaches "completed".

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/incident_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Status helpers
// ─────────────────────────────────────────────────────────────────────────────

const _statusOrder = [
  'pending',
  'hospital_assigned',
  'ambulance_assigned',
  'completed',
];

String _statusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Reported';
    case 'hospital_assigned':
      return 'Hospital Assigned';
    case 'ambulance_assigned':
      return 'Ambulance Assigned';
    case 'completed':
      return 'Completed';
    default:
      return status;
  }
}

String _statusFriendlyMessage(String status) {
  switch (status) {
    case 'pending':
      return 'Searching for nearby hospitals...\nPlease stay calm and keep your phone nearby.';
    case 'hospital_assigned':
      return 'A hospital has accepted your case.\nAn ambulance is being dispatched.';
    case 'ambulance_assigned':
      return 'An ambulance is on the way to you!\nPlease remain at your current location.';
    case 'completed':
      return 'Your emergency has been handled.\nThank you for using our service.';
    default:
      return 'Processing your request...';
  }
}

Color _statusColor(String status, BuildContext context) {
  switch (status) {
    case 'pending':
      return Colors.orange;
    case 'hospital_assigned':
      return Colors.blue;
    case 'ambulance_assigned':
      return Colors.teal;
    case 'completed':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TrackingScreen widget
// ─────────────────────────────────────────────────────────────────────────────

class TrackingScreen extends StatefulWidget {
  final int incidentId;

  const TrackingScreen({super.key, required this.incidentId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Timer? _timer;

  IncidentData? _incident;
  String? _errorMessage;
  bool _isLoading = true;

  static const _pollInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _fetchAndUpdate();
    _timer = Timer.periodic(_pollInterval, (_) => _fetchAndUpdate());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAndUpdate() async {
    try {
      final data = await IncidentService.fetchIncident(widget.incidentId);
      if (!mounted) return;
      setState(() {
        _incident = data;
        _errorMessage = null;
        _isLoading = false;
      });
      // Stop polling once the incident is completed
      if (data.status == 'completed') {
        _timer?.cancel();
        _timer = null;
      }
    } on IncidentServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    }
  }

  // Manual retry — clears error, re-shows loading and restarts poll
  void _retry() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _timer?.cancel();
    _fetchAndUpdate();
    _timer = Timer.periodic(_pollInterval, (_) => _fetchAndUpdate());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Incident #${widget.incidentId}'),
        centerTitle: true,
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading incident data...'),
          ],
        ),
      );
    }

    if (_errorMessage != null && _incident == null) {
      // Hard error — nothing to show yet
      return _ErrorView(message: _errorMessage!, onRetry: _retry);
    }

    final incident = _incident!;

    return RefreshIndicator(
      onRefresh: _fetchAndUpdate,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Soft error banner (we still have stale data)
            if (_errorMessage != null)
              _ErrorBanner(message: _errorMessage!, onRetry: _retry),

            // Status card with friendly message
            _StatusCard(incident: incident),
            const SizedBox(height: 20),

            // Visual stepper
            _StatusStepper(currentStatus: incident.status),
            const SizedBox(height: 20),

            // Emergency details
            _DetailsCard(incident: incident),
            const SizedBox(height: 20),

            // Assignment info (only when assigned)
            if (incident.assignedHospitalId != null ||
                incident.assignedAmbulanceId != null)
              _AssignmentCard(incident: incident),

            const SizedBox(height: 8),

            // Polling hint
            if (incident.status != 'completed')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Auto-refreshing every 3 s  •  Pull to refresh',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final IncidentData incident;
  const _StatusCard({required this.incident});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(incident.status, context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: color.withValues(alpha: 0.1),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(incident.status).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _statusFriendlyMessage(incident.status),
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status Stepper ────────────────────────────────────────────────────────────

class _StatusStepper extends StatelessWidget {
  final String currentStatus;
  const _StatusStepper({required this.currentStatus});

  @override
  Widget build(BuildContext context) {
    final currentIndex = _statusOrder.indexOf(currentStatus);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'PROGRESS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ..._statusOrder.asMap().entries.map((entry) {
              final index = entry.key;
              final status = entry.value;
              final isDone = index < currentIndex;
              final isCurrent = index == currentIndex;
              final isPending = index > currentIndex;

              Color dotColor;
              IconData dotIcon;
              if (isDone) {
                dotColor = Colors.green;
                dotIcon = Icons.check_circle;
              } else if (isCurrent) {
                dotColor = Colors.blue;
                dotIcon = Icons.radio_button_checked;
              } else {
                dotColor = Colors.grey.shade300;
                dotIcon = Icons.radio_button_unchecked;
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Icon(dotIcon, color: dotColor, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusLabel(status),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isPending
                                ? Colors.grey
                                : Colors.black87,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'NOW',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Connector line (not after last item)
                  if (index < _statusOrder.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Container(
                        width: 2,
                        height: 20,
                        color: isDone ? Colors.green.shade200 : Colors.grey.shade200,
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Emergency Details Card ────────────────────────────────────────────────────

class _DetailsCard extends StatelessWidget {
  final IncidentData incident;
  const _DetailsCard({required this.incident});

  @override
  Widget build(BuildContext context) {
    final hasAny = incident.emergencyType != null ||
        incident.severity != null ||
        incident.departmentNeeded != null;

    if (!hasAny) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EMERGENCY DETAILS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            if (incident.emergencyType != null)
              _DetailRow(
                icon: Icons.local_hospital_outlined,
                label: 'Type',
                value: _toTitle(incident.emergencyType!),
              ),
            if (incident.severity != null)
              _DetailRow(
                icon: Icons.warning_amber_outlined,
                label: 'Severity',
                value: _toTitle(incident.severity!),
                valueColor: _severityColor(incident.severity!),
              ),
            if (incident.departmentNeeded != null)
              _DetailRow(
                icon: Icons.medical_services_outlined,
                label: 'Department',
                value: _toTitle(incident.departmentNeeded!),
              ),
          ],
        ),
      ),
    );
  }

  static Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.deepOrange;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.black87;
    }
  }

  static String _toTitle(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Assignment Card ──────────────────────────────────────────────────────────

class _AssignmentCard extends StatelessWidget {
  final IncidentData incident;
  const _AssignmentCard({required this.incident});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ASSIGNMENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            if (incident.assignedHospitalId != null)
              _DetailRow(
                icon: Icons.local_hospital,
                label: 'Hospital ID',
                value: '#${incident.assignedHospitalId}',
              ),
            if (incident.assignedAmbulanceId != null)
              _DetailRow(
                icon: Icons.airport_shuttle,
                label: 'Ambulance ID',
                value: '#${incident.assignedAmbulanceId}',
              ),
          ],
        ),
      ),
    );
  }
}

// ── Error widgets ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.orange.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
