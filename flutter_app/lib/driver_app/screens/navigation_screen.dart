// lib/driver_app/screens/navigation_screen.dart
//
// Driver Navigation Screen:
//   • Shows incident details and patient GPS marker
//   • Polls for hospital assignment every 3-5 seconds
//   • Draws route line (OSRM or straight line fallback) once hospital is assigned
//   • Displays driver live position blue dot
//   • Supports panning/zooming without reset, plus recenter/fit camera button
//   • Cancel and system back return to Home (TODO for future cancellation lifecycle)

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
import 'package:ambulance_app/driver_app/widgets/navigation_status_chip.dart';

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

  // Driver blue dot GPS tracking
  LatLng? _driverLocation;
  StreamSubscription<Position>? _positionSubscription;

  // Routing state
  RouteResult? _route;
  bool _fetchingRoute = false;
  int? _lastHospitalId;

  // Camera tracking
  bool _hasFittedHospital = false;

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

  // ── Driver GPS Tracking (Blue Dot) ─────────────────────────────────────────

  Future<void> _initDriverLocationTracking() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        // Silently skip: map still functions without blue dot
        return;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _driverLocation = LatLng(last.latitude, last.longitude);
        });
      }

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (pos) {
          if (!mounted) return;
          setState(() {
            _driverLocation = LatLng(pos.latitude, pos.longitude);
          });
        },
        onError: (e) {
          debugPrint('[NavigationScreen] Position stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('[NavigationScreen] GPS init error: $e');
    }
  }

  // ── Initial Fetch & Polling ────────────────────────────────────────────────

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

      // If hospital is already assigned, fetch route and fit camera
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

      // If hospital assigned or changed, fetch route
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

  // ── Error Handling ─────────────────────────────────────────────────────────

  void _handleFetchError(String error, {required bool isInitial}) {
    if (!mounted) return;

    // 401 Session expired
    if (error.contains('Session expired') || error.contains('401')) {
      _stopPolling();
      AuthService.clearSession();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (route) => false,
      );
      return;
    }

    // 403 or 404
    if (error.contains('403') ||
        error.contains('404') ||
        error.contains('not assigned') ||
        error.contains('not authorized') ||
        error.contains('not found')) {
      _stopPolling();
      _showFatalDialog(
        title: 'Incident Unavailable',
        message: error,
      );
      return;
    }

    // Non-blocking error: keep existing map state, show banner
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
              Navigator.of(context).pop(); // Back to Home
            },
            child: const Text('Return to Home'),
          ),
        ],
      ),
    );
  }

  // ── Hospital Assigned & Routing ────────────────────────────────────────────

  Future<void> _handleHospitalAssigned(
    DriverIncidentHospital hospital, {
    required bool autoFitCamera,
  }) async {
    if (_fetchingRoute && _lastHospitalId == hospital.id) return;

    _lastHospitalId = hospital.id;
    setState(() => _fetchingRoute = true);

    final routeResult = await RoutingService.getRoute(
      origin: _incident!.location,
      destination: hospital.location,
    );

    if (!mounted) return;

    setState(() {
      _route = routeResult;
      _fetchingRoute = false;
    });

    if (autoFitCamera && !_hasFittedHospital) {
      _hasFittedHospital = true;
      _fitCameraToIncidentAndHospital();
    }
  }

  // ── Camera Control ─────────────────────────────────────────────────────────

  void _fitCameraToIncidentAndHospital() {
    if (_incident == null) return;

    final points = <LatLng>[_incident!.location];
    if (_incident!.assignedHospital != null) {
      points.add(_incident!.assignedHospital!.location);
    }
    if (_driverLocation != null) {
      points.add(_driverLocation!);
    }

    if (points.length == 1) {
      _mapController.move(_incident!.location, 15.0);
    } else {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(70),
        ),
      );
    }
  }

  void _recenterOrFit() {
    if (_incident == null) return;
    if (_incident!.assignedHospital != null) {
      _fitCameraToIncidentAndHospital();
    } else {
      _mapController.move(_incident!.location, 15.0);
    }
  }

  // ── Cancel & Back Navigation ───────────────────────────────────────────────

  Future<void> _handleCancel() async {
    // Ask for confirmation before releasing the incident
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

    // Show a loading indicator while the cancellation is in flight
    _stopPolling();
    setState(() => _loading = true);

    try {
      await DriverApiService.cancelIncident(
        ambulanceId: widget.ambulanceId,
        incidentId: widget.incidentId,
      );
      if (!mounted) return;
      // Pop back to Home; home screen will refresh incident list
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      // Restart polling so the driver isn't stuck
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
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: cs.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading incident #${widget.incidentId}...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : _incident == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Failed to load incident details.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: cs.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _fetchInitialIncident,
                          child: const Text('Retry'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back to Home'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Top Strip (Incident summary + minimal Cancel button)
                      IncidentTopStrip(
                        incident: _incident!,
                        onCancel: _handleCancel,
                      ),

                      // Non-blocking network error banner (keeps map alive)
                      if (_nonBlockingError != null)
                        Container(
                          width: double.infinity,
                          color: cs.errorContainer,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 16,
                                color: cs.onErrorContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Sync issue: $_nonBlockingError',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onErrorContainer,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
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

                      // Map fills all remaining space
                      Expanded(
                        child: Stack(
                          children: [
                            _buildMap(),

                            // Status Chip over map (top center)
                            Positioned(
                              top: 12,
                              left: 16,
                              right: 16,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: NavigationStatusChip(
                                  hospital: _incident!.assignedHospital,
                                  route: _route,
                                  isRouting: _fetchingRoute,
                                ),
                              ),
                            ),

                            // Recenter / Fit button (bottom right)
                            Positioned(
                              bottom: 28,
                              right: 14,
                              child: FloatingActionButton.small(
                                heroTag: 'recenter_fit_fab',
                                backgroundColor: cs.surface,
                                foregroundColor: cs.primary,
                                tooltip: 'Recenter / Fit route',
                                elevation: 4,
                                onPressed: _recenterOrFit,
                                child: const Icon(
                                  Icons.crop_free_rounded,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildMap() {
    final inc = _incident!;
    final hosp = inc.assignedHospital;

    final markers = <Marker>[
      // Incident Marker (Red)
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

    // Hospital Marker (Distinct color + icon)
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
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: Color(0xFF00796B),
              size: 24,
            ),
          ),
        ),
      );
    }

    // Driver Current Position Marker (Blue dot)
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
                  color: Colors.black38,
                  blurRadius: 5,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final polylines = <Polyline>[];
    if (_route != null && _route!.points.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _route!.points,
          strokeWidth: _route!.isFallback ? 3.0 : 4.5,
          color: _route!.isFallback
              ? const Color(0xFFE65100).withValues(alpha: 0.8)
              : const Color(0xFF1565C0),
          pattern: _route!.isFallback
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
