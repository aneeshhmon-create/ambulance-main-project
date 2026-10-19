// lib/driver_app/screens/navigation_screen.dart
//
// Driver Navigation Screen — dual-phase routing
//
//  Phase 1  (hospital NOT yet assigned)
//    • Blue solid polyline  : driver current position → patient/incident location
//    • Status chip          : "En route to patient • X km (Y min)"  or  spinner
//    • Camera fit           : driver + patient
//
//  Phase 2  (hospital assigned)
//    • Blue solid polyline  : driver → patient          (same as phase 1)
//    • Teal solid polyline  : patient → hospital        (new leg)
//    • Status chip          : "Hospital: <name> • X km (Y min)"
//    • Camera fit           : driver + patient + hospital (auto-fits once)
//
//  Markers
//    • Red  pin   : incident / patient location
//    • Teal badge : hospital (phase 2 only)
//    • Blue dot   : driver live GPS position

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:ambulance_app/driver_app/models/incident_detail.dart';
import 'package:ambulance_app/driver_app/screens/auth_page.dart';
import 'package:ambulance_app/driver_app/services/auth_service.dart';
import 'package:ambulance_app/driver_app/services/driver_api_service.dart'
    hide LatLng;
import 'package:ambulance_app/driver_app/services/routing_service.dart';
import 'package:ambulance_app/driver_app/widgets/incident_top_strip.dart';

class NavigationScreen extends StatefulWidget {
  final int incidentId;
  final int ambulanceId;

  const NavigationScreen({
    super.key,
    required this.incidentId,
    required this.ambulanceId,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();

  DriverIncidentDetail? _incident;
  bool _loading = true;
  String? _nonBlockingError;
  bool _pollingActive = false;
  Timer? _pollTimer;

  // ── Driver live position ──────────────────────────────────────────────────
  LatLng? _driverLocation;
  StreamSubscription<Position>? _positionSubscription;

  // ── Phase 1: driver → patient route ──────────────────────────────────────
  RouteResult? _toPatientRoute;
  bool _fetchingToPatient = false;
  // Re-fetch driver→patient route when driver moves more than ~50 m
  LatLng? _lastRouteDriverPos;

  // ── Phase 2: patient → hospital route ────────────────────────────────────
  RouteResult? _toHospitalRoute;
  bool _fetchingToHospital = false;
  int? _lastHospitalId;

  // ── Camera ────────────────────────────────────────────────────────────────
  bool _hasFittedCamera = false; // fitted to driver+patient on first GPS fix
  bool _hasFittedHospital = false; // fitted to all 3 on hospital assign

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDriverLocationTracking();
    _fetchInitialIncident();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopPolling();
    } else if (state == AppLifecycleState.resumed) {
      _startPolling();
    }
  }

  // ── Driver GPS tracking ───────────────────────────────────────────────────

  Future<void> _initDriverLocationTracking() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        final ll = LatLng(last.latitude, last.longitude);
        setState(() => _driverLocation = ll);
        _maybeRefetchToPatientRoute(ll);
      }

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15, // only fire when moved ≥ 15 m
        ),
      ).listen(
        (pos) {
          if (!mounted) return;
          final ll = LatLng(pos.latitude, pos.longitude);
          setState(() => _driverLocation = ll);
          _maybeRefetchToPatientRoute(ll);
          // On first GPS fix, fit camera to driver + patient
          if (!_hasFittedCamera && _incident != null) {
            _hasFittedCamera = true;
            _fitCamera();
          }
        },
        onError: (e) => debugPrint('[NavScreen] GPS stream error: $e'),
      );
    } catch (e) {
      debugPrint('[NavScreen] GPS init error: $e');
    }
  }

  /// Re-fetch the driver→patient route if driver moved > 50 m from last fetch.
  void _maybeRefetchToPatientRoute(LatLng newPos) {
    if (_incident == null) return;
    if (_fetchingToPatient) return;

    final last = _lastRouteDriverPos;
    if (last != null) {
      final movedM = const Distance().as(LengthUnit.Meter, last, newPos);
      if (movedM < 50) return; // not enough movement to re-route
    }

    _fetchToPatientRoute(newPos);
  }

  Future<void> _fetchToPatientRoute(LatLng from) async {
    if (_incident == null || _fetchingToPatient) return;
    _fetchingToPatient = true;
    _lastRouteDriverPos = from;

    final result = await RoutingService.getRoute(
      origin: from,
      destination: _incident!.location,
    );

    if (!mounted) return;
    setState(() {
      _toPatientRoute = result;
      _fetchingToPatient = false;
    });
  }

  // ── Initial fetch & polling ───────────────────────────────────────────────

  Future<void> _fetchInitialIncident() async {
    setState(() {
      _loading = true;
      _nonBlockingError = null;
    });
    try {
      final detail = await DriverApiService.fetchIncidentDetail(
        ambulanceId: widget.ambulanceId,
        incidentId: widget.incidentId,
      );
      if (!mounted) return;
      setState(() {
        _incident = detail;
        _loading = false;
      });

      // Kick off driver→patient route if we already have a GPS fix
      if (_driverLocation != null) {
        _fetchToPatientRoute(_driverLocation!);
      }

      // If hospital already assigned at load time, fetch patient→hospital route
      if (detail.assignedHospital != null) {
        _handleHospitalAssigned(detail.assignedHospital!, autoFitCamera: true);
      }

      _startPolling();
    } on String catch (e) {
      _handleFetchError(e, isInitial: true);
    } catch (e) {
      _handleFetchError(e.toString(), isInitial: true);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollingActive = true;
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollIncidentDetail(),
    );
  }

  void _stopPolling() {
    _pollingActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollIncidentDetail() async {
    if (!_pollingActive || !mounted) return;
    try {
      final detail = await DriverApiService.fetchIncidentDetail(
        ambulanceId: widget.ambulanceId,
        incidentId: widget.incidentId,
      );
      if (!mounted) return;

      final previousHospitalId = _incident?.assignedHospital?.id;
      final newHospital = detail.assignedHospital;

      setState(() {
        _incident = detail;
        _nonBlockingError = null;
      });

      // New hospital assigned? fetch patient→hospital route
      if (newHospital != null && newHospital.id != previousHospitalId) {
        _handleHospitalAssigned(
          newHospital,
          autoFitCamera: !_hasFittedHospital,
        );
      }
    } on String catch (e) {
      _handleFetchError(e, isInitial: false);
    } catch (e) {
      _handleFetchError(e.toString(), isInitial: false);
    }
  }

  // ── Hospital assigned ─────────────────────────────────────────────────────

  Future<void> _handleHospitalAssigned(
    DriverIncidentHospital hospital, {
    required bool autoFitCamera,
  }) async {
    if (_fetchingToHospital && _lastHospitalId == hospital.id) return;
    _lastHospitalId = hospital.id;
    setState(() => _fetchingToHospital = true);

    // Route: patient location → hospital location
    final result = await RoutingService.getRoute(
      origin: _incident!.location,
      destination: hospital.location,
    );
    if (!mounted) return;
    setState(() {
      _toHospitalRoute = result;
      _fetchingToHospital = false;
    });

    if (autoFitCamera && !_hasFittedHospital) {
      _hasFittedHospital = true;
      _fitCamera();
    }
  }

  // ── Error Handling ────────────────────────────────────────────────────────

  void _handleFetchError(String error, {required bool isInitial}) {
    if (!mounted) return;

    if (error.contains('Session expired') || error.contains('401')) {
      _stopPolling();
      AuthService.clearSession();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (route) => false,
      );
      return;
    }

    if (error.contains('403') ||
        error.contains('404') ||
        error.contains('not assigned') ||
        error.contains('not authorized') ||
        error.contains('not found')) {
      _stopPolling();
      _showFatalDialog(title: 'Incident Unavailable', message: error);
      return;
    }

    setState(() {
      if (isInitial) _loading = false;
      _nonBlockingError = error;
    });
  }

  void _showFatalDialog({required String title, required String message}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Return to Home'),
          ),
        ],
      ),
    );
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  void _fitCamera() {
    if (_incident == null) return;
    final points = <LatLng>[_incident!.location];
    if (_driverLocation != null) points.add(_driverLocation!);
    if (_incident!.assignedHospital != null) {
      points.add(_incident!.assignedHospital!.location);
    }

    if (points.length == 1) {
      _mapController.move(points.first, 15.0);
    } else {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(70),
        ),
      );
    }
  }

  void _recenterOrFit() => _fitCamera();

  // ── Cancel ────────────────────────────────────────────────────────────────

  Future<void> _handleCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Mission?'),
        content: const Text(
          'This will release the incident so other ambulances can accept it. '
          'Are you sure you want to cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Mission'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _stopPolling();
    setState(() => _loading = true);

    try {
      await DriverApiService.cancelIncident(
        ambulanceId: widget.ambulanceId,
        incidentId: widget.incidentId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _startPolling();
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not cancel: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ── UI Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleCancel();
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        body: _loading
            ? _buildLoadingState(theme, cs)
            : _incident == null
                ? _buildErrorState(cs)
                : _buildMapState(theme, cs),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme, ColorScheme cs) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Loading incident #${widget.incidentId}...',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );

  Widget _buildErrorState(ColorScheme cs) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Failed to load incident details.',
              style: TextStyle(color: cs.error),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _fetchInitialIncident,
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      );

  Widget _buildMapState(ThemeData theme, ColorScheme cs) {
    final hasHospital = _incident!.assignedHospital != null;

    return Column(
      children: [
        // ── Top strip ─────────────────────────────────────────────────────
        IncidentTopStrip(
          incident: _incident!,
          onCancel: _handleCancel,
        ),

        // ── Network error banner ──────────────────────────────────────────
        if (_nonBlockingError != null)
          Container(
            width: double.infinity,
            color: cs.errorContainer,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded,
                    size: 16, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sync issue: $_nonBlockingError',
                    style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: _pollIncidentDetail,
                  child: Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Map + overlays ────────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              _buildMap(),

              // ── Status chip – top-center ────────────────────────────────
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _buildStatusChip(theme, cs, hasHospital),
                ),
              ),

              // ── Route legend – bottom-left ──────────────────────────────
              Positioned(
                bottom: 28,
                left: 14,
                child: _buildLegend(cs, hasHospital),
              ),

              // ── Fit/recenter FAB – bottom-right ─────────────────────────
              Positioned(
                bottom: 28,
                right: 14,
                child: FloatingActionButton.small(
                  heroTag: 'recenter_fit_fab',
                  backgroundColor: cs.surface,
                  foregroundColor: cs.primary,
                  tooltip: 'Fit all',
                  elevation: 4,
                  onPressed: _recenterOrFit,
                  child: const Icon(Icons.crop_free_rounded, size: 22),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Status chip ───────────────────────────────────────────────────────────

  Widget _buildStatusChip(
      ThemeData theme, ColorScheme cs, bool hasHospital) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasHospital
                ? const Color(0xFF00796B).withValues(alpha: 0.5)
                : cs.primary.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasHospital) ...[
              // Phase 1 ─ en route to patient
              Icon(Icons.directions_car_rounded,
                  size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _phase1StatusText(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_fetchingToPatient) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: cs.primary,
                  ),
                ),
              ],
            ] else ...[
              // Phase 2 ─ hospital assigned
              const Icon(Icons.local_hospital_rounded,
                  size: 18, color: Color(0xFF00796B)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _phase2StatusText(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_fetchingToHospital) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: cs.primary),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _phase1StatusText() {
    if (_toPatientRoute == null) return 'Navigating to patient…';
    final km = _toPatientRoute!.distanceKm.toStringAsFixed(1);
    final min = _toPatientRoute!.durationMinutes.ceil();
    if (_toPatientRoute!.isFallback) {
      return 'To patient • ~$km km (direct)';
    }
    return 'To patient • $km km ($min min)';
  }

  String _phase2StatusText() {
    final hosp = _incident!.assignedHospital!;
    if (_toHospitalRoute == null) return 'Hospital: ${hosp.name}';
    final km = _toHospitalRoute!.distanceKm.toStringAsFixed(1);
    final min = _toHospitalRoute!.durationMinutes.ceil();
    if (_toHospitalRoute!.isFallback) {
      return '${hosp.name} • ~$km km (direct)';
    }
    return '${hosp.name} • $km km ($min min)';
  }

  // ── Legend ────────────────────────────────────────────────────────────────

  Widget _buildLegend(ColorScheme cs, bool hasHospital) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendRow(
            color: const Color(0xFF1565C0),
            label: 'You → Patient',
          ),
          if (hasHospital) ...[
            const SizedBox(height: 4),
            _legendRow(
              color: const Color(0xFF00796B),
              label: 'Patient → Hospital',
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendRow({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  // ── Map ───────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final inc = _incident!;
    final hosp = inc.assignedHospital;

    // ── Markers ────────────────────────────────────────────────────────────
    final markers = <Marker>[
      // Patient / incident (Red pin)
      Marker(
        point: inc.location,
        width: 44,
        height: 44,
        child: const Icon(
          Icons.location_on_rounded,
          color: Color(0xFFD32F2F),
          size: 42,
        ),
      ),
    ];

    // Hospital (Teal badge)
    if (hosp != null) {
      markers.add(
        Marker(
          point: hosp.location,
          width: 42,
          height: 42,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF00796B), width: 2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: const Icon(Icons.local_hospital_rounded,
                color: Color(0xFF00796B), size: 24),
          ),
        ),
      );
    }

    // Driver blue dot
    if (_driverLocation != null) {
      markers.add(
        Marker(
          point: _driverLocation!,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1976D2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black38, blurRadius: 5, offset: Offset(0, 1))
              ],
            ),
          ),
        ),
      );
    }

    // ── Polylines ──────────────────────────────────────────────────────────
    final polylines = <Polyline>[];

    // Leg 1: driver → patient  (blue)
    if (_toPatientRoute != null && _toPatientRoute!.points.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _toPatientRoute!.points,
          strokeWidth: _toPatientRoute!.isFallback ? 3.0 : 4.5,
          color: _toPatientRoute!.isFallback
              ? const Color(0xFF1565C0).withValues(alpha: 0.5)
              : const Color(0xFF1565C0),
          pattern: _toPatientRoute!.isFallback
              ? StrokePattern.dashed(segments: const [10, 8])
              : const StrokePattern.solid(),
        ),
      );
    }

    // Leg 2: patient → hospital  (teal) — only in phase 2
    if (_toHospitalRoute != null && _toHospitalRoute!.points.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _toHospitalRoute!.points,
          strokeWidth: _toHospitalRoute!.isFallback ? 3.0 : 4.5,
          color: _toHospitalRoute!.isFallback
              ? const Color(0xFF00796B).withValues(alpha: 0.5)
              : const Color(0xFF00796B),
          pattern: _toHospitalRoute!.isFallback
              ? StrokePattern.dashed(segments: const [10, 8])
              : const StrokePattern.solid(),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: inc.location,
        initialZoom: 14.5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.team19.ambulance.driver',
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
        const SimpleAttributionWidget(
          source: Text('© OpenStreetMap contributors'),
          alignment: Alignment.bottomLeft,
        ),
      ],
    );
  }
}
