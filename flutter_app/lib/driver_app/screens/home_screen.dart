// lib/driver_app/screens/home_screen.dart
//
// Driver App – Home Screen
//
// Layout (matching the hand-sketch requirements):
//
//  ┌──────────────────────────────────────────────────┐
//  │  [avatar]  Hello, <name>      Online ◉  [logout] │
//  │            KL-01-AA-1234                          │
//  │            ALS                                    │
//  ├──────────────────────────────────────────────────┤
//  │  [Details]  Incident N  (severity / type)  [Accept] │
//  │  ─────────────────────────────────────────────   │
//  │  (empty state when offline or no incidents)       │
//  ├──────────────────────────────────────────────────┤
//  │  ╔══════════════════════════════════════════════╗ │
//  │  ║  HomeFooter (status / future features)       ║ │
//  │  ╚══════════════════════════════════════════════╝ │
//  └──────────────────────────────────────────────────┘
//
// State machine:
//   • Toggle online  → PATCH /ambulances/{id}/online   (also starts GPS timer)
//   • GPS timer      → every 7 s: PATCH /ambulances/{id}/location
//   • Poll timer     → every 8 s: GET  /ambulances/{id}/incidents
//                                  GET  /ambulances/{id}/assignment
//   • Accept         → POST /ambulances/{id}/incidents/{iid}/accept →
//                      navigate to IncidentAcceptedScreen (race 409 shows snackbar)
//   • Details        → showModalBottomSheet with full incident fields

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:ambulance_app/driver_app/models/driver.dart';
import 'package:ambulance_app/driver_app/models/incident_detail.dart';
import 'package:ambulance_app/driver_app/services/auth_service.dart';
import 'package:ambulance_app/driver_app/services/driver_api_service.dart';
import 'package:ambulance_app/driver_app/screens/auth_page.dart';
import 'package:ambulance_app/driver_app/screens/navigation_screen.dart';
import 'package:ambulance_app/driver_app/widgets/home_footer.dart';
import 'package:latlong2/latlong.dart' as ll2;

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
  String? _incidentError;

  final Set<int> _acceptingIds = {};

  Timer? _pollTimer;
  Timer? _locationTimer;

  // Guard: prevents duplicate navigation if two rapid checks both find an
  // active assignment (e.g. initState + first poll overlap on slow networks).
  bool _checkingAssignment = false;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isOnline = widget.ambulance.isOnline;
    if (_isOnline) {
      _startPolling();
      _startLocationSharing();
    }
    // After the first frame (Navigator is ready), check if there is already
    // an active incident this driver accepted before logging out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeNavigationIfNeeded();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _locationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isOnline) {
      _poll(); // immediate refresh on foreground
      _resumeNavigationIfNeeded(); // re-check active assignment on foreground
    }
  }

  // ── Resume active navigation ──────────────────────────────────────────────

  /// Checks the backend for an active assigned incident.
  /// If found, automatically navigates to [NavigationScreen] so the driver
  /// can continue navigating after a logout-and-login or app restart.
  Future<void> _resumeNavigationIfNeeded() async {
    if (_checkingAssignment || !mounted) return;
    _checkingAssignment = true;
    try {
      final assignment =
          await DriverApiService.fetchAssignment(widget.ambulance.id);
      if (!mounted) return;
      if (assignment.assigned && assignment.incidentId != null) {
        // Show a brief banner so the driver understands what is happening.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resuming your active mission…'),
            duration: Duration(seconds: 2),
          ),
        );
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NavigationScreen(
              incidentId: assignment.incidentId!,
              ambulanceId: widget.ambulance.id,
            ),
          ),
        );
        // Returned from NavigationScreen — refresh incident list.
        if (mounted) _poll();
      }
    } catch (e) {
      // Non-fatal: if the check fails (network hiccup, 401 etc.) we simply
      // leave the driver on the home screen; the normal polling will proceed.
      debugPrint('[HomeScreen] _resumeNavigationIfNeeded error: $e');
    } finally {
      _checkingAssignment = false;
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
      setState(() {
        _loadingIncidents = true;
        _incidentError = null;
      });
      final incidents = await DriverApiService.fetchIncidents(id);
      if (mounted) {
        setState(() {
          _incidents = incidents;
          _loadingIncidents = false;
        });
      }
    } on String catch (e) {
      if (!mounted) return;
      // 401 — session expired: redirect to auth
      if (e.contains('Session expired') || e.contains('401')) {
        await AuthService.clearSession();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthPage()),
          (route) => false,
        );
        return;
      }
      setState(() {
        _loadingIncidents = false;
        _incidentError = e;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingIncidents = false;
          _incidentError = e.toString();
        });
      }
      debugPrint('[HomeScreen] fetchIncidents error: $e');
    }
  }

  // ── Live GPS location sharing ────────────────────────────────────────────────

  void _startLocationSharing() {
    _locationTimer?.cancel();
    // Push location every 7 seconds while online
    _locationTimer = Timer.periodic(
      const Duration(seconds: 7),
      (_) => _pushLocation(),
    );
  }

  void _stopLocationSharing() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _pushLocation() async {
    if (!_isOnline || !mounted) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return; // silently skip if permission was revoked
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      await DriverApiService.updateLocation(
        ambulanceId: widget.ambulance.id,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    } catch (e) {
      // Non-fatal: GPS or network hiccup; will retry next tick
      debugPrint('[HomeScreen] _pushLocation error: $e');
    }
  }

  // ── Online toggle ─────────────────────────────────────────────────────────────

  Future<void> _toggleOnline(bool value) async {
    if (_togglingOnline) return;
    setState(() => _togglingOnline = true);

    double? lat, lng;
    if (value) {
      // Request permission and get first GPS fix when going online
      try {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.deniedForever) {
          if (mounted) {
            _showError(
              'Location permission is permanently denied. '
              'Enable it in Settings to go online.',
            );
          }
          setState(() => _togglingOnline = false);
          return;
        }
        if (perm == LocationPermission.denied) {
          if (mounted) {
            _showError(
              'Location permission denied. '
              'Grant permission to share your location.',
            );
          }
          setState(() => _togglingOnline = false);
          return;
        }
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            _showError('GPS is disabled. Enable location services to go online.');
          }
          setState(() => _togglingOnline = false);
          return;
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (e) {
        // Non-fatal: proceed without initial location if GPS times out
        debugPrint('[HomeScreen] GPS init error: $e');
      }
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
          _incidentError = null;
        }
      });
      if (value) {
        _startPolling();
        _startLocationSharing();
      } else {
        _stopPolling();
        _stopLocationSharing();
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

    // Convert IncidentRequest to DriverIncidentDetail so NavigationScreen can
    // immediately render the map, patient location, and incident details without waiting.
    final initialDetail = DriverIncidentDetail(
      id: incident.id,
      status: 'ambulance_assigned',
      severity: incident.severity,
      emergencyType: incident.emergencyType,
      symptoms: incident.symptoms,
      victims: incident.victims,
      departmentNeeded: incident.departmentNeeded,
      transcript: incident.transcript,
      location: ll2.LatLng(incident.location.lat, incident.location.lng),
      createdAt: incident.createdAt,
      assignedHospital: null,
    );

    // Concurrently trigger backend accept call
    final acceptFuture = DriverApiService.acceptIncident(
      ambulanceId: widget.ambulance.id,
      incidentId: incident.id,
    );

    try {
      // Immediately open NavigationScreen!
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NavigationScreen(
            incidentId: incident.id,
            ambulanceId: widget.ambulance.id,
            initialDetail: initialDetail,
            acceptFuture: acceptFuture,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _acceptingIds.remove(incident.id));
        _poll();
      }
    }
  }

  // ── Show details bottom sheet ─────────────────────────────────────────────────

  void _showDetails(IncidentRequest incident) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _IncidentDetailSheet(
        incident: incident,
        accepting: _acceptingIds.contains(incident.id),
        onAccept: () {
          Navigator.of(ctx).pop();
          _accept(incident);
        },
      ),
    );
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
    _stopLocationSharing();
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
            HomeFooter(isOnline: _isOnline),
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
                      activeThumbColor: const Color(0xFF388E3C),
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
              'Go online to receive emergency requests.',
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

    // Show error state with retry button
    if (_incidentError != null && _incidents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, size: 56, color: cs.outlineVariant),
              const SizedBox(height: 16),
              Text(
                'Failed to load requests',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                _incidentError!,
                textAlign: TextAlign.center,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _poll,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
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
              'No incoming requests',
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'New requests will appear here automatically.',
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
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) => _IncidentTile(
          incident: _incidents[i],
          accepting: _acceptingIds.contains(_incidents[i].id),
          onAccept: () => _accept(_incidents[i]),
          onDetails: () => _showDetails(_incidents[i]),
        ),
      ),
    );
  }
}

// ── Incident Tile ──────────────────────────────────────────────────────────────

class _IncidentTile extends StatelessWidget {
  final IncidentRequest incident;
  final bool accepting;
  final VoidCallback onAccept;
  final VoidCallback onDetails;

  const _IncidentTile({
    required this.incident,
    required this.accepting,
    required this.onAccept,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sev = incident.severity;
    final sevColor = _severityColor(sev);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Severity bar
          Container(
            width: 4,
            height: 64,
            decoration: BoxDecoration(
              color: sevColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),

          // Middle: incident info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Severity badge
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: sevColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: sevColor.withValues(alpha: 0.4)),
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
                const SizedBox(height: 3),
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
                    Icon(Icons.people_rounded, size: 13, color: cs.onSurfaceVariant),
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
          const SizedBox(width: 8),

          // Right: Details + Accept buttons
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Details button (outlined, smaller)
              SizedBox(
                height: 30,
                child: OutlinedButton(
                  onPressed: onDetails,
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Details',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Accept button (filled)
              accepting
                  ? const SizedBox(
                      width: 64,
                      height: 30,
                      child: Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                    )
                  : SizedBox(
                      height: 30,
                      child: FilledButton(
                        onPressed: onAccept,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 0),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Accept',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Incident Detail Bottom Sheet ─────────────────────────────────────────────

class _IncidentDetailSheet extends StatelessWidget {
  final IncidentRequest incident;
  final bool accepting;
  final VoidCallback onAccept;

  const _IncidentDetailSheet({
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
    final since = _timeSince(incident.createdAt);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                children: [
                  // Title row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Incident #${incident.id}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: sevColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _severityLabel(sev),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reported $since',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Divider(height: 24),

                  // Emergency type
                  _DetailRow(
                    icon: Icons.emergency_rounded,
                    label: 'Emergency Type',
                    value: incident.emergencyType ?? '—',
                    theme: theme,
                    cs: cs,
                  ),
                  const SizedBox(height: 12),

                  // Victims
                  _DetailRow(
                    icon: Icons.people_rounded,
                    label: 'Victims',
                    value: '${incident.victims}',
                    theme: theme,
                    cs: cs,
                  ),
                  const SizedBox(height: 12),

                  // Department
                  if (incident.departmentNeeded != null) ...[
                    _DetailRow(
                      icon: Icons.local_hospital_rounded,
                      label: 'Department Needed',
                      value: incident.departmentNeeded!,
                      theme: theme,
                      cs: cs,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Distance
                  if (incident.distanceKm != null) ...[
                    _DetailRow(
                      icon: Icons.navigation_rounded,
                      label: 'Distance',
                      value:
                          '${incident.distanceKm!.toStringAsFixed(2)} km away',
                      theme: theme,
                      cs: cs,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Symptoms
                  if (incident.symptoms.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sick_rounded,
                            size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Symptoms',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: incident.symptoms
                                    .map(
                                      (s) => Chip(
                                        label: Text(s,
                                            style: const TextStyle(
                                                fontSize: 12)),
                                        padding: EdgeInsets.zero,
                                        visualDensity:
                                            VisualDensity.compact,
                                        backgroundColor:
                                            cs.surfaceContainerHighest,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Transcript
                  if (incident.transcript != null &&
                      incident.transcript!.isNotEmpty) ...[
                    const Divider(height: 20),
                    Text(
                      'Call Transcript',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        incident.transcript!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Accept button in details sheet
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: accepting ? null : onAccept,
                      icon: accepting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        accepting ? 'Accepting…' : 'Accept Incident',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Human-readable time since the incident was reported.
  String _timeSince(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt.toLocal());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} days ago';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;
  final ColorScheme cs;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
