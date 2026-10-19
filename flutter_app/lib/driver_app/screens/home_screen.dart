// lib/driver_app/screens/home_screen.dart
//
// Driver App – Home Screen
//
// Layout (matching the hand-sketch requirements):
//
//  ┌──────────────────────────────────────────────────┐
//  │  Hello, <name>       ┌───────────┐  Online ◉   │
//  │  KL-01-AA-1234       │  [avatar] │             │
//  │  ALS                 └───────────┘             │
//  ├──────────────────────────────────────────────────┤
//  │  Incident 1  (severity badge / type)  [Accept]  │
//  │  ─────────────────────────────────────────────  │
//  │  Incident 2  …                        [Accept]  │
//  │  (empty state when offline or no incidents)     │
//  ├──────────────────────────────────────────────────┤
//  │  ╔══════════════════════════════════════════════╗ │
//  │  ║  Active Assignment (hidden when idle)        ║ │
//  │  ╚══════════════════════════════════════════════╝ │
//  └──────────────────────────────────────────────────┘
//
// State machine:
//   • Toggle online  → PATCH /ambulances/{id}/online  (also starts GPS updates)
//   • Polling        → every 8 s: GET /ambulances/{id}/incidents
//                                  GET /ambulances/{id}/assignment
//   • Accept         → POST  /ambulances/{id}/incidents/{iid}/accept  →
//                      race 409 shows snackbar; success refreshes state

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:ambulance_app/driver_app/models/driver.dart';
import 'package:ambulance_app/driver_app/services/auth_service.dart';
import 'package:ambulance_app/driver_app/services/driver_api_service.dart';
import 'package:ambulance_app/driver_app/screens/auth_page.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Color _severityColor(String? severity) {
  switch (severity?.toLowerCase()) {
    case 'critical':
      return const Color(0xFFD32F2F);
    case 'high':
      return const Color(0xFFF57C00);
    case 'medium':
      return const Color(0xFFF9A825);
    case 'low':
      return const Color(0xFF388E3C);
    default:
      return const Color(0xFF607D8B);
  }
}

String _severityLabel(String? s) =>
    s == null ? 'Unknown' : s[0].toUpperCase() + s.substring(1);

// ── Home Screen ───────────────────────────────────────────────────────────────

class DriverHomeScreen extends StatefulWidget {
  final DriverModel driver;
  final AmbulanceModel ambulance;

  const DriverHomeScreen({
    super.key,
    required this.driver,
    required this.ambulance,
  });

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  // ── State ───────────────────────────────────────────────────────────────────

  late bool _isOnline;
  bool _togglingOnline = false;

  List<IncidentRequest> _incidents = [];
  bool _loadingIncidents = false;

  ActiveAssignment? _assignment;

  final Set<int> _acceptingIds = {};

  Timer? _pollTimer;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isOnline = widget.ambulance.isOnline;
    if (_isOnline) _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isOnline) {
      _poll(); // immediate refresh on foreground
    }
  }

  // ── Polling ──────────────────────────────────────────────────────────────────

  void _startPolling() {
    _poll(); // immediate first tick
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    if (!_isOnline || !mounted) return;
    final id = widget.ambulance.id;
    try {
      final incidents = await DriverApiService.fetchIncidents(id);
      if (mounted) setState(() => _incidents = incidents);
    } catch (e) {
      // silently ignore transient network errors during polling
      debugPrint('[HomeScreen] fetchIncidents error: $e');
    }
    try {
      final assignment = await DriverApiService.fetchAssignment(id);
      if (mounted) setState(() => _assignment = assignment);
    } catch (e) {
      debugPrint('[HomeScreen] fetchAssignment error: $e');
    }
  }

  // ── Online toggle ─────────────────────────────────────────────────────────────

  Future<void> _toggleOnline(bool value) async {
    if (_togglingOnline) return;
    setState(() => _togglingOnline = true);

    double? lat, lng;
    if (value) {
      // Try to get GPS; non-fatal if denied
      try {
        final perm = await Geolocator.checkPermission();
        LocationPermission granted = perm;
        if (perm == LocationPermission.denied) {
          granted = await Geolocator.requestPermission();
        }
        if (granted != LocationPermission.denied &&
            granted != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 6),
            ),
          );
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {}
    }

    try {
      await DriverApiService.setOnline(
        ambulanceId: widget.ambulance.id,
        isOnline: value,
        lat: lat,
        lng: lng,
      );
      await AuthService.updateStoredOnlineState(value);
      if (!mounted) return;
      setState(() {
        _isOnline = value;
        if (!value) {
          _incidents = [];
          _assignment = null;
        }
      });
      if (value) {
        _startPolling();
      } else {
        _stopPolling();
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
  }

  // ── Accept incident ───────────────────────────────────────────────────────────

  Future<void> _accept(IncidentRequest incident) async {
    if (_acceptingIds.contains(incident.id)) return;
    setState(() => _acceptingIds.add(incident.id));
    try {
      await DriverApiService.acceptIncident(
        ambulanceId: widget.ambulance.id,
        incidentId: incident.id,
      );
      // Immediately poll to refresh lists
      await _poll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Incident #${incident.id} accepted — en route!'),
            backgroundColor: const Color(0xFF388E3C),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _acceptingIds.remove(incident.id));
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────────

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out / Change Ambulance'),
        content: const Text(
          'This will sign you out and clear your active ambulance selection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _stopPolling();
    await AuthService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────────

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme, cs),
            const Divider(height: 1, thickness: 1),
            Expanded(child: _buildIncidentList(theme, cs)),
            _buildFooter(theme, cs),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    final driver = widget.driver;
    final ambulance = widget.ambulance;

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          CircleAvatar(
            radius: 26,
            backgroundColor: cs.primaryContainer,
            backgroundImage:
                driver.photoUrl != null ? NetworkImage(driver.photoUrl!) : null,
            child: driver.photoUrl == null
                ? Text(
                    driver.name.isNotEmpty
                        ? driver.name[0].toUpperCase()
                        : 'D',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          // Name + ambulance info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${driver.name.split(' ').first}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ambulance.registrationNumber,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: cs.primary,
                  ),
                ),
                if (ambulance.vehicleType != null)
                  Text(
                    ambulance.vehicleType!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          // Online toggle
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _isOnline ? 'Online' : 'Offline',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _isOnline ? const Color(0xFF388E3C) : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              _togglingOnline
                  ? const SizedBox(
                      width: 36,
                      height: 20,
                      child: Center(
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                    )
                  : Switch(
                      value: _isOnline,
                      onChanged: _toggleOnline,
                      activeColor: const Color(0xFF388E3C),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
            ],
          ),
          // Sign-out button
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: 'Sign out / Change ambulance',
            onPressed: _handleSignOut,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  // ── Incident list ──────────────────────────────────────────────────────────────

  Widget _buildIncidentList(ThemeData theme, ColorScheme cs) {
    if (!_isOnline) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'You are offline',
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Toggle Online to start receiving\nincident requests.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.outline,
              ),
            ),
          ],
        ),
      );
    }

    if (_loadingIncidents && _incidents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_incidents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 56, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'No pending incidents',
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'New requests will appear here\nautomatically.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.outline,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _poll,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _incidents.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) => _IncidentTile(
          incident: _incidents[i],
          accepting: _acceptingIds.contains(_incidents[i].id),
          onAccept: () => _accept(_incidents[i]),
        ),
      ),
    );
  }

  // ── Footer / Active Assignment ─────────────────────────────────────────────────

  Widget _buildFooter(ThemeData theme, ColorScheme cs) {
    final asgn = _assignment;

    // Active assignment card
    if (asgn != null && asgn.assigned) {
      return Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.emergency_rounded,
                      color: cs.onPrimaryContainer, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Active: Incident #${asgn.incidentId}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _severityColor(asgn.severity),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _severityLabel(asgn.severity),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (asgn.emergencyType != null)
                Text(
                  asgn.emergencyType!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person_pin_rounded,
                      size: 14, color: cs.onPrimaryContainer.withOpacity(0.7)),
                  const SizedBox(width: 4),
                  Text(
                    asgn.patientName ?? 'Patient',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onPrimaryContainer.withOpacity(0.8)),
                  ),
                  if (asgn.distanceToPatientKm != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.straighten_rounded,
                        size: 14,
                        color: cs.onPrimaryContainer.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text(
                      '${asgn.distanceToPatientKm!.toStringAsFixed(1)} km',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer.withOpacity(0.8)),
                    ),
                  ],
                ],
              ),
              if (asgn.hospitalName != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.local_hospital_rounded,
                        size: 14,
                        color: cs.onPrimaryContainer.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        asgn.hospitalName!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onPrimaryContainer.withOpacity(0.8)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'Awaiting hospital assignment…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onPrimaryContainer.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Idle footer
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isOnline
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 14,
            color: _isOnline ? const Color(0xFF388E3C) : cs.outline,
          ),
          const SizedBox(width: 8),
          Text(
            _isOnline ? 'Waiting for incident requests…' : 'Go online to receive calls',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _isOnline ? cs.onSurface : cs.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Incident Tile ──────────────────────────────────────────────────────────────

class _IncidentTile extends StatelessWidget {
  final IncidentRequest incident;
  final bool accepting;
  final VoidCallback onAccept;

  const _IncidentTile({
    required this.incident,
    required this.accepting,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sev = incident.severity;
    final sevColor = _severityColor(sev);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: severity bar
          Container(
            width: 4,
            height: 56,
            decoration: BoxDecoration(
              color: sevColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          // Middle: incident info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: sevColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: sevColor.withOpacity(0.4)),
                      ),
                      child: Text(
                        _severityLabel(sev),
                        style: TextStyle(
                          color: sevColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Incident #${incident.id}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  incident.emergencyType ?? 'Emergency',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.people_rounded,
                        size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '${incident.victims} victim${incident.victims != 1 ? "s" : ""}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (incident.distanceKm != null) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.navigation_rounded,
                          size: 13, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '${incident.distanceKm!.toStringAsFixed(1)} km',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                    if (incident.departmentNeeded != null) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.local_hospital_outlined,
                          size: 13, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          incident.departmentNeeded!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: Accept button
          accepting
              ? const SizedBox(
                  width: 64,
                  height: 36,
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Accept',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
        ],
      ),
    );
  }
}
