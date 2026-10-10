import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/routes.dart';
import '../models/incident.dart';

/// Screen displaying AI triage extraction results and incident status.
///
/// Route: `/result`
/// Argument: [Incident] object
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    this.incident,
    this.onCall108,
  });

  final Incident? incident;
  final Future<void> Function()? onCall108;

  Future<void> _call108(BuildContext context) async {
    if (onCall108 != null) {
      await onCall108!();
      return;
    }
    final uri = Uri.parse('tel:108');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not place call to 108')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call failed: $e')),
        );
      }
    }
  }

  void _returnHome(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.root,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIncident = incident ??
        ModalRoute.of(context)?.settings.arguments as Incident?;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _returnHome(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Emergency Response'),
          backgroundColor: Colors.red[700],
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: () => _returnHome(context),
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: effectiveIncident == null
              ? _buildMissingIncidentView(context)
              : _buildContent(context, effectiveIncident),
        ),
      ),
    );
  }

  Widget _buildMissingIncidentView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            const Text(
              'No incident data received.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _returnHome(context),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Incident inc) {
    final isFallback = _isFallbackExtraction(inc);
    final zeroHospitals = inc.broadcasts.isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Text(
            'We understood your report',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Incident #${inc.id}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // ── Fallback Notice OR Severity Badge ────────────────────────────────
          if (isFallback)
            _buildFallbackNotice()
          else
            _buildSeverityBadge(inc.severity),

          const SizedBox(height: 20),

          // ── Summary Card ─────────────────────────────────────────────────────
          _buildSummaryCard(context, inc, isFallback),

          // ── Symptoms (hidden if empty) ───────────────────────────────────────
          if (inc.symptoms.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSymptomsSection(context, inc.symptoms),
          ],

          const SizedBox(height: 20),

          // ── Transcript Card ──────────────────────────────────────────────────
          _buildTranscriptCard(context, inc.transcript),

          const SizedBox(height: 20),

          // ── Status Line ──────────────────────────────────────────────────────
          _buildStatusLine(context, inc.status),

          const SizedBox(height: 16),

          // ── Hospitals Notified / Warning ─────────────────────────────────────
          _buildHospitalsSection(inc),

          const SizedBox(height: 32),

          // ── Primary Action: Track my request ─────────────────────────────────
          ElevatedButton.icon(
            key: const ValueKey('track_my_request_button'),
            onPressed: () {
              Navigator.of(context).pushNamed(
                AppRoutes.tracking,
                arguments: inc.id,
              );
            },
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Track my request', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),

          const SizedBox(height: 12),

          // ── Secondary Action: Call 108 ───────────────────────────────────────
          _buildCall108Button(context, zeroHospitals),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Severity Badge ───────────────────────────────────────────────────────────

  Widget _buildSeverityBadge(String? severityRaw) {
    final severity = (severityRaw ?? 'unspecified').trim().toLowerCase();

    final (label, color, bgColor, borderColor, icon) = switch (severity) {
      'critical' => (
          'CRITICAL SEVERITY',
          Colors.red[900]!,
          Colors.red[50]!,
          Colors.red[300]!,
          Icons.error_outline_rounded,
        ),
      'high' => (
          'HIGH SEVERITY',
          Colors.orange[900]!,
          Colors.orange[50]!,
          Colors.orange[300]!,
          Icons.warning_amber_rounded,
        ),
      'medium' => (
          'MEDIUM SEVERITY',
          Colors.amber[900]!,
          Colors.amber[50]!,
          Colors.amber[400]!,
          Icons.info_outline_rounded,
        ),
      'low' => (
          'LOW SEVERITY',
          Colors.green[900]!,
          Colors.green[50]!,
          Colors.green[300]!,
          Icons.check_circle_outline_rounded,
        ),
      _ => (
          severityRaw?.toUpperCase() ?? 'SEVERITY ASSESSED',
          Colors.blueGrey[900]!,
          Colors.blueGrey[50]!,
          Colors.blueGrey[200]!,
          Icons.medical_information_outlined,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Fallback Neutral Notice ──────────────────────────────────────────────────

  Widget _buildFallbackNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        border: Border.all(color: Colors.blueGrey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.blueGrey[700], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "We couldn't fully analyse your message, but help is still being arranged",
              style: TextStyle(
                color: Colors.blueGrey[900],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary Card ─────────────────────────────────────────────────────────────

  Widget _buildSummaryCard(BuildContext context, Incident inc, bool isFallback) {
    return Card(
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSummaryRow(
              icon: Icons.local_hospital_rounded,
              label: 'Emergency Type',
              value: isFallback ? 'General Emergency' : (inc.emergencyType ?? 'General Emergency'),
            ),
            const Divider(height: 20),
            _buildSummaryRow(
              icon: Icons.domain_rounded,
              label: 'Department Needed',
              value: inc.departmentNeeded ?? 'Emergency Care',
            ),
            const Divider(height: 20),
            _buildSummaryRow(
              icon: Icons.people_outline_rounded,
              label: 'Victims',
              value: '${inc.victims} ${inc.victims == 1 ? 'person' : 'people'}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[700]),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  // ── Symptoms Section ─────────────────────────────────────────────────────────

  Widget _buildSymptomsSection(BuildContext context, List<String> symptoms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Identified Symptoms',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: symptoms.map((symptom) {
            return Chip(
              label: Text(symptom),
              backgroundColor: Colors.red[50],
              labelStyle: TextStyle(
                color: Colors.red[900],
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              side: BorderSide(color: Colors.red.shade200),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Transcript Card ──────────────────────────────────────────────────────────

  Widget _buildTranscriptCard(BuildContext context, String? transcript) {
    final hasTranscript = transcript != null && transcript.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over_rounded, size: 18, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Text(
                'What we heard',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: SelectableText(
                hasTranscript ? transcript : 'No transcript available',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: hasTranscript ? Colors.black87 : Colors.grey[600],
                  fontStyle: hasTranscript ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status Line ──────────────────────────────────────────────────────────────

  Widget _buildStatusLine(BuildContext context, String status) {
    final statusText = _formatStatus(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_rounded, size: 20, color: Colors.blue[800]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: Colors.blue[900],
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hospitals Notified ───────────────────────────────────────────────────────

  Widget _buildHospitalsSection(Incident inc) {
    if (inc.broadcasts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.shade400, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber[900], size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No nearby hospital found yet',
                style: TextStyle(
                  color: Colors.amber[950],
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final count = inc.broadcasts.length;
    return Row(
      children: [
        Icon(Icons.local_hospital_outlined, size: 18, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Text(
          '$count ${count == 1 ? 'hospital' : 'hospitals'} notified',
          style: TextStyle(
            color: Colors.grey[800],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Call 108 Button ──────────────────────────────────────────────────────────

  Widget _buildCall108Button(BuildContext context, bool zeroHospitals) {
    if (zeroHospitals) {
      // Highlighted prominent secondary button when 0 hospitals are broadcast
      return ElevatedButton.icon(
        key: const ValueKey('call_108_button'),
        onPressed: () => _call108(context),
        icon: const Icon(Icons.call_rounded),
        label: const Text('Call 108 Now', style: TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber[800],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      key: const ValueKey('call_108_button'),
      onPressed: () => _call108(context),
      icon: Icon(Icons.call_rounded, color: Colors.red[700]),
      label: Text(
        'Call 108',
        style: TextStyle(fontSize: 16, color: Colors.red[700], fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.red.shade700, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static bool _isFallbackExtraction(Incident inc) {
    final type = inc.emergencyType?.trim().toLowerCase();
    return type == null || type.isEmpty || type == 'unspecified' || type == 'unknown';
  }

  static String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Waiting for a hospital to accept';
      case 'hospital_assigned':
        return 'Hospital found';
      case 'ambulance_assigned':
        return 'Ambulance on the way';
      case 'completed':
        return 'Incident resolved';
      case 'cancelled':
        return 'Incident cancelled';
      default:
        return status.replaceAll('_', ' ');
    }
  }
}
