// lib/driver_app/screens/navigation_screen.dart
//
// Google-Maps-style driving navigation screen.
//
//  ┌──────────────────────────────────────────────────────────────┐
//  │  IncidentTopStrip (incident # / severity / expand / Cancel)  │
//  ├──────────────────────────────────────────────────────────────┤
//  │                        OSM Map                               │
//  │  ┌──────────────────────────────────────────────────────┐   │
//  │  │ Status chip (top-centre)                             │   │
//  │  │                                                      │   │
//  │  │   ── Blue polyline  : driver → patient (trimmed) ──  │   │
//  │  │   ── Teal polyline  : patient → hospital            ─│   │
//  │  │                                                      │   │
//  │  │   ● Red pin   : patient/incident                     │   │
//  │  │   ● Teal badge: hospital (once assigned)             │   │
//  │  │   ↑ Blue arrow: driver (rotates, animates position)  │   │
//  │  │                                                      │   │
//  │  │ [Legend]              [Re-follow FAB] [Fit FAB]      │   │
//  │  └──────────────────────────────────────────────────────┘   │
//  └──────────────────────────────────────────────────────────────┘
//
//  Driving-mode behaviours
//  ───────────────────────
//  • Camera auto-follows driver in heading-up mode (map rotates to put
//    direction of travel at top).  A 200 m look-ahead offset keeps the
//    road ahead visible rather than the driver being centred.
//  • Driver marker is a navigation arrow (Icons.navigation_rounded) that
//    rotates to the current bearing.  Position is smoothly interpolated
//    between GPS fixes using an AnimationController (600 ms, easeOut).
//  • Bearing is smoothed (EMA, 30 % blending) to prevent jitter.
//  • Route trimming: the driver → patient polyline has already-passed
//    segments removed on every GPS fix (closest vertex search).
//  • User pan/pinch disables auto-follow; a prominent FAB re-enables it.
//  • Hospital polling runs every 4 s; when assigned a second (teal)
//    polyline is added for patient → hospital.

import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

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

// ── constants ─────────────────────────────────────────────────────────────────

/// Zoom level used in auto-follow (driving) mode.
const double _kDrivingZoom = 16.8;

/// How far ahead of the driver (metres) to centre the camera so more road
/// is visible in the upper portion of the screen.
const double _kLookAheadMetres = 200.0;

/// Minimum driver movement (metres) before re-fetching the to-patient route.
const double _kRerouteThresholdM = 60.0;

// ── helpers ───────────────────────────────────────────────────────────────────

/// Computes the initial bearing (degrees, 0 = N, 90 = E) from [a] to [b].
double _calcBearing(LatLng a, LatLng b) {
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final dLng = (b.longitude - a.longitude) * pi / 180;
  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

/// Smoothly blends [current] bearing toward [next] (handles 0/360 wrap).
double _smoothBearing(double current, double next) {
  var diff = next - current;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return (current + diff * 0.3 + 360) % 360;
}

/// Returns a point [metres] ahead of [pos] in [bearingDeg] direction.
LatLng _pointAhead(LatLng pos, double bearingDeg, double metres) {
  const r = 6371000.0;
  final d = metres / r;
  final b = bearingDeg * pi / 180;
  final lat1 = pos.latitude * pi / 180;
  final lng1 = pos.longitude * pi / 180;
  final lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b));
  final lng2 =
      lng1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2));
  return LatLng(lat2 * 180 / pi, lng2 * 180 / pi);
}

/// Returns the sublist of [points] from the vertex closest to [driver] onward.
/// Inserts [driver] as the new first point so the line starts exactly at the
/// driver's position (no visual gap).
List<LatLng> _trimRoute(List<LatLng> points, LatLng driver) {
  if (points.length < 2) return [driver];
  int best = 0;
  double bestDistSq = double.infinity;
  for (int i = 0; i < points.length; i++) {
    final dx = points[i].latitude - driver.latitude;
    final dy = points[i].longitude - driver.longitude;
    final dSq = dx * dx + dy * dy;
    if (dSq < bestDistSq) {
      bestDistSq = dSq;
      best = i;
    }
  }
  if (best >= points.length - 1) return [driver, points.last];
  return [driver, ...points.sublist(best + 1)];
}

// ── widget ────────────────────────────────────────────────────────────────────

class NavigationScreen extends StatefulWidget {
  final int incidentId;
  final int ambulanceId;
  final DriverIncidentDetail? initialDetail;
  final Future<void>? acceptFuture;

  const NavigationScreen({
    super.key,
    required this.incidentId,
    required this.ambulanceId,
    this.initialDetail,
    this.acceptFuture,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final MapController _mapController = MapController();

  // ── incident state ────────────────────────────────────────────────────────
  DriverIncidentDetail? _incident;
  bool _loading = true;
  String? _nonBlockingError;
  bool _pollingActive = false;
  Timer? _pollTimer;
  bool _fatalErrorOccurred = false;

  // ── driver GPS & animation ────────────────────────────────────────────────
  /// Raw GPS position from the stream (used as animation target).
  LatLng? _rawDriverPos;
  /// Smoothly animated position shown on the map.
  LatLng? _animPos;
  /// Previous animation start point.
  LatLng? _animFrom;
  /// Current bearing in degrees (smoothed EMA).
  double _bearing = 0.0;

  late AnimationController _posAnimCtrl;
  StreamSubscription<Position>? _gpsStream;

  // ── camera / follow mode ──────────────────────────────────────────────────
  bool _isFollowing = true;

  // ── routes ────────────────────────────────────────────────────────────────
  /// Full OSRM route: driver → patient (updated on re-route).
  RouteResult? _toPatientRoute;
  /// Trimmed subset of _toPatientRoute shown on map.
  List<LatLng>? _trimmedToPatient;
  bool _fetchingToPatient = false;
  LatLng? _lastRouteFetchPos;

  /// Full OSRM route: patient → hospital (fetched once on assignment).
  RouteResult? _toHospitalRoute;
  bool _fetchingToHospital = false;
  int? _lastHospitalId;

  // Camera has been auto-fitted at least once after hospital assigned
  bool _hasFittedHospital = false;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _posAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(_onAnimTick);

    if (widget.initialDetail != null) {
      _incident = widget.initialDetail;
      _loading = false;
    }

    AuthService.saveActiveIncidentId(widget.incidentId);
    _initGps();

    if (widget.acceptFuture != null) {
      _handleAcceptFuture();
    } else {
      _fetchInitialIncident();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _gpsStream?.cancel();
    _posAnimCtrl.dispose();
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

  // ── GPS & animation ───────────────────────────────────────────────────────

  Future<void> _initGps() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;

      // Seed with last known so the marker appears immediately
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        final ll = LatLng(last.latitude, last.longitude);
        _rawDriverPos = ll;
        _animPos = ll;
        _animFrom = ll;
        setState(() {});
        _maybeReroute(ll);
      }

      _gpsStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // fire every 10 m of movement
        ),
      ).listen(_onGpsPosition, onError: (e) {
        debugPrint('[NavScreen] GPS error: $e');
      });
    } catch (e) {
      debugPrint('[NavScreen] GPS init: $e');
    }
  }

  void _onGpsPosition(Position pos) {
    if (!mounted) return;
    final newPos = LatLng(pos.latitude, pos.longitude);

    // ── bearing ──────────────────────────────────────────────────────────
    double rawBearing;
    if (pos.heading > 0) {
      rawBearing = pos.heading; // device compass / GPS heading (0-360)
    } else if (_animPos != null) {
      rawBearing = _calcBearing(_animPos!, newPos); // computed from movement
    } else {
      rawBearing = _bearing;
    }
    _bearing = _smoothBearing(_bearing, rawBearing);

    // ── animate position ─────────────────────────────────────────────────
    _animFrom = _animPos ?? newPos;
    _rawDriverPos = newPos;
    _posAnimCtrl
      ..stop()
      ..reset()
      ..forward();

    // ── re-route if moved enough ─────────────────────────────────────────
    _maybeReroute(newPos);
  }

  /// AnimationController tick — interpolates position and drives camera.
  void _onAnimTick() {
    if (_animFrom == null || _rawDriverPos == null) return;
    final t = CurvedAnimation(
      parent: _posAnimCtrl,
      curve: Curves.easeOut,
    ).value;

    final lat = lerpDouble(_animFrom!.latitude, _rawDriverPos!.latitude, t)!;
    final lng = lerpDouble(_animFrom!.longitude, _rawDriverPos!.longitude, t)!;
    final interpolated = LatLng(lat, lng);

    setState(() {
      _animPos = interpolated;
      // Update trimmed route on every animation tick for smooth visual
      if (_toPatientRoute != null) {
        _trimmedToPatient =
            _trimRoute(_toPatientRoute!.points, interpolated);
      }
    });

    if (_isFollowing) _driveCamera(interpolated);
  }

  /// Moves + rotates the camera to keep the driver centred in heading-up mode.
  void _driveCamera(LatLng driverPos) {
    // Put the look-ahead point at the camera centre so more road is visible
    final cameraCenter = _pointAhead(driverPos, _bearing, _kLookAheadMetres);
    try {
      _mapController.moveAndRotate(cameraCenter, _kDrivingZoom, -_bearing);
    } catch (_) {
      // MapController may not be ready during build; ignore silently
    }
  }

  void _maybeReroute(LatLng pos) {
    if (_incident == null) return;
    if (_fetchingToPatient) return;
    final last = _lastRouteFetchPos;
    if (last != null) {
      final movedM = const Distance().as(LengthUnit.Meter, last, pos);
      if (movedM < _kRerouteThresholdM) return;
    }
    _fetchToPatientRoute(pos);
  }

  Future<void> _fetchToPatientRoute(LatLng from) async {
    if (_incident == null || _fetchingToPatient) return;
    setState(() => _fetchingToPatient = true);
    _lastRouteFetchPos = from;
    final result = await RoutingService.getRoute(
      origin: from,
      destination: _incident!.location,
    );
    if (!mounted) return;
    setState(() {
      _toPatientRoute = result;
      _trimmedToPatient = _animPos != null
          ? _trimRoute(result.points, _animPos!)
          : result.points;
      _fetchingToPatient = false;
    });
  }

  // ── incident fetch & polling ──────────────────────────────────────────────

  Future<void> _fetchInitialIncident() async {
    if (_incident == null) {
      setState(() {
        _loading = true;
        _nonBlockingError = null;
      });
    }
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

      // Kick off driver→patient route now that we know the incident location
      if (_animPos != null) _fetchToPatientRoute(_animPos!);

      if (detail.assignedHospital != null) {
        _handleHospitalAssigned(detail.assignedHospital!, autoFit: true);
      }
      _startPolling();
    } on String catch (e) {
      _handleFetchError(e, isInitial: true);
    } catch (e) {
      _handleFetchError(e.toString(), isInitial: true);
    }
  }

  void _handleAcceptFuture() {
    widget.acceptFuture!.then((_) {
      if (!mounted) return;
      AuthService.saveActiveIncidentId(widget.incidentId);
      _startPolling(immediate: true);
    }).catchError((e) {
      if (!mounted) return;
      AuthService.clearActiveIncidentId();
      _stopPolling();
      final err = e.toString();
      final msg = err.contains('409') ||
              err.toLowerCase().contains('already accepted')
          ? 'Another ambulance has already accepted this incident.'
          : err;
      _showFatalDialog(title: 'Could Not Accept Incident', message: msg);
    });
  }

  void _startPolling({bool immediate = false}) {
    _pollTimer?.cancel();
    _pollingActive = true;
    if (immediate) {
      _pollIncidentDetail();
    }
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
      final prevHospId = _incident?.assignedHospital?.id;
      setState(() {
        _incident = detail;
        _nonBlockingError = null;
      });
      if (detail.assignedHospital != null &&
          detail.assignedHospital!.id != prevHospId) {
        _handleHospitalAssigned(
          detail.assignedHospital!,
          autoFit: !_hasFittedHospital,
        );
      }
    } on String catch (e) {
      _handleFetchError(e, isInitial: false);
    } catch (e) {
      _handleFetchError(e.toString(), isInitial: false);
    }
  }

  // ── hospital routing ──────────────────────────────────────────────────────

  Future<void> _handleHospitalAssigned(
    DriverIncidentHospital hospital, {
    required bool autoFit,
  }) async {
    if (_fetchingToHospital && _lastHospitalId == hospital.id) return;
    _lastHospitalId = hospital.id;
    setState(() => _fetchingToHospital = true);

    final result = await RoutingService.getRoute(
      origin: _incident!.location,
      destination: hospital.location,
    );
    if (!mounted) return;
    setState(() {
      _toHospitalRoute = result;
      _fetchingToHospital = false;
    });

    if (autoFit && !_hasFittedHospital) {
      _hasFittedHospital = true;
      _fitAll();
    }
  }

  // ── error handling ────────────────────────────────────────────────────────

  void _handleFetchError(String error, {required bool isInitial}) {
    if (!mounted) return;
    if (error.contains('Session expired') || error.contains('401')) {
      _stopPolling();
      AuthService.clearSession();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (r) => false,
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
    _fatalErrorOccurred = true;
    AuthService.clearActiveIncidentId();
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

  // ── camera helpers ────────────────────────────────────────────────────────

  void _fitAll() {
    if (_incident == null) return;
    final pts = <LatLng>[_incident!.location];
    if (_animPos != null) pts.add(_animPos!);
    if (_incident!.assignedHospital != null) {
      pts.add(_incident!.assignedHospital!.location);
    }
    try {
      if (pts.length == 1) {
        _mapController.moveAndRotate(pts.first, 15.0, 0);
      } else {
        _mapController.rotate(0); // North-up for overview
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.all(70),
          ),
        );
      }
    } catch (_) {}
    // After fitting, stay in manual mode so user can see overview
    setState(() => _isFollowing = false);
  }

  /// Re-enable follow mode: animate camera back to driver and rotate to heading.
  void _reFollow() {
    setState(() => _isFollowing = true);
    if (_animPos != null) _driveCamera(_animPos!);
  }

  // ── cancel ────────────────────────────────────────────────────────────────

  Future<void> _handleCancel() async {
    if (_fatalErrorOccurred) return;
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
      await AuthService.clearActiveIncidentId();
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

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: _fatalErrorOccurred,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_fatalErrorOccurred) _handleCancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _loading
            ? _buildLoader(theme, cs)
            : _incident == null
                ? _buildError(cs)
                : _buildDrivingView(theme, cs),
      ),
    );
  }

  Widget _buildLoader(ThemeData theme, ColorScheme cs) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Loading incident #${widget.incidentId}…',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );

  Widget _buildError(ColorScheme cs) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            const Text('Failed to load incident details.'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _fetchInitialIncident,
                child: const Text('Retry')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      );

  Widget _buildDrivingView(ThemeData theme, ColorScheme cs) {
    final hasHospital = _incident!.assignedHospital != null;

    return Column(
      children: [
        // ── top strip ──────────────────────────────────────────────────────
        IncidentTopStrip(
          incident: _incident!,
          onCancel: _handleCancel,
        ),

        // ── network error banner ───────────────────────────────────────────
        if (_nonBlockingError != null)
          Container(
            width: double.infinity,
            color: cs.errorContainer,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Icon(Icons.wifi_off_rounded,
                  size: 16, color: cs.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sync issue: $_nonBlockingError',
                  style:
                      TextStyle(fontSize: 12, color: cs.onErrorContainer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _pollIncidentDetail,
                child: Text('Retry',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
          ),

        // ── map ────────────────────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              _buildMap(),

              // Status chip — top-centre
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _buildStatusChip(theme, cs, hasHospital),
                ),
              ),

              // Route legend — bottom-left
              Positioned(
                bottom: 90,
                left: 14,
                child: _buildLegend(cs, hasHospital),
              ),

              // Re-follow FAB — only when user has panned away
              if (!_isFollowing)
                Positioned(
                  bottom: 90,
                  right: 14,
                  child: FloatingActionButton.extended(
                    heroTag: 'refollow_fab',
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    elevation: 6,
                    onPressed: _reFollow,
                    icon: const Icon(Icons.navigation_rounded, size: 20),
                    label: const Text('Follow',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),

              // Fit-all FAB — always visible at bottom-right
              Positioned(
                bottom: 28,
                right: 14,
                child: FloatingActionButton.small(
                  heroTag: 'fitall_fab',
                  backgroundColor: cs.surface,
                  foregroundColor: cs.primary,
                  elevation: 4,
                  tooltip: 'Fit all',
                  onPressed: _fitAll,
                  child: const Icon(Icons.crop_free_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── status chip ──────────────────────────────────────────────────────────

  Widget _buildStatusChip(ThemeData t, ColorScheme cs, bool hasHospital) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: hasHospital
                ? const Color(0xFF00796B).withValues(alpha: 0.5)
                : cs.primary.withValues(alpha: 0.45),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasHospital) ...[
              Icon(Icons.directions_car_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _toPatientText(),
                  style: t.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_fetchingToPatient) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.8, color: cs.primary),
                ),
              ],
            ] else ...[
              const Icon(Icons.local_hospital_rounded,
                  size: 18, color: Color(0xFF00796B)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _toHospitalText(),
                  style: t.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_fetchingToHospital) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.8, color: cs.primary),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _toPatientText() {
    if (_toPatientRoute == null) return 'Routing to patient…';
    final km = _toPatientRoute!.distanceKm.toStringAsFixed(1);
    final min = _toPatientRoute!.durationMinutes.ceil();
    return _toPatientRoute!.isFallback
        ? 'To patient  ~$km km'
        : 'To patient  $km km · $min min';
  }

  String _toHospitalText() {
    final h = _incident!.assignedHospital!;
    if (_toHospitalRoute == null) return 'Hospital: ${h.name}';
    final km = _toHospitalRoute!.distanceKm.toStringAsFixed(1);
    final min = _toHospitalRoute!.durationMinutes.ceil();
    return _toHospitalRoute!.isFallback
        ? '${h.name}  ~$km km'
        : '${h.name}  $km km · $min min';
  }

  // ── legend ────────────────────────────────────────────────────────────────

  Widget _buildLegend(ColorScheme cs, bool hasHospital) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendRow(const Color(0xFF1565C0), 'You → Patient'),
          if (hasHospital) ...[
            const SizedBox(height: 4),
            _legendRow(const Color(0xFF00796B), 'Patient → Hospital'),
          ],
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 3,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      );

  // ── map ───────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final inc = _incident!;
    final hosp = inc.assignedHospital;

    // ── markers ────────────────────────────────────────────────────────
    final markers = <Marker>[
      // Patient / incident — red pin
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

    // Hospital — teal badge
    if (hosp != null) {
      markers.add(Marker(
        point: hosp.location,
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF00796B), width: 2.3),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26,
                  blurRadius: 5,
                  offset: Offset(0, 2))
            ],
          ),
          child: const Icon(Icons.local_hospital_rounded,
              color: Color(0xFF00796B), size: 26),
        ),
      ));
    }

    // Driver — animated navigation arrow
    if (_animPos != null) {
      // In follow mode the map is already rotated to heading-up, so the
      // icon (pointing screen-up) naturally faces the direction of travel.
      // In manual (North-up) mode we must rotate the icon by the bearing.
      final iconAngle = _isFollowing ? 0.0 : _bearing * pi / 180;
      markers.add(Marker(
        point: _animPos!,
        width: 52,
        height: 52,
        child: Transform.rotate(
          angle: iconAngle,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.45),
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
                const BoxShadow(
                  color: Colors.black38,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.navigation_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ));
    }

    // ── polylines ──────────────────────────────────────────────────────
    final polylines = <Polyline>[];

    // Leg 1: driver → patient (trimmed, blue)
    final leg1 = _trimmedToPatient ??
        (_toPatientRoute?.points);
    if (leg1 != null && leg1.length >= 2) {
      final isFb = _toPatientRoute?.isFallback ?? true;
      polylines.add(Polyline(
        points: leg1,
        strokeWidth: isFb ? 3.5 : 5.0,
        color: isFb
            ? const Color(0xFF1565C0).withValues(alpha: 0.55)
            : const Color(0xFF1565C0),
        pattern: isFb
            ? StrokePattern.dashed(segments: const [12, 8])
            : const StrokePattern.solid(),
        borderStrokeWidth: 1.5,
        borderColor: Colors.white.withValues(alpha: 0.3),
      ));
    }

    // Leg 2: patient → hospital (teal)
    if (_toHospitalRoute != null &&
        _toHospitalRoute!.points.length >= 2) {
      final isFb = _toHospitalRoute!.isFallback;
      polylines.add(Polyline(
        points: _toHospitalRoute!.points,
        strokeWidth: isFb ? 3.5 : 5.0,
        color: isFb
            ? const Color(0xFF00796B).withValues(alpha: 0.55)
            : const Color(0xFF00796B),
        pattern: isFb
            ? StrokePattern.dashed(segments: const [12, 8])
            : const StrokePattern.solid(),
        borderStrokeWidth: 1.5,
        borderColor: Colors.white.withValues(alpha: 0.3),
      ));
    }

    // ── flutter_map ────────────────────────────────────────────────────
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _animPos ?? inc.location,
        initialZoom: _animPos != null ? _kDrivingZoom : 14.5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        // Detect user pan/pinch → disable auto-follow
        onPositionChanged: (_, hasGesture) {
          if (hasGesture && _isFollowing) {
            setState(() => _isFollowing = false);
            // Reset map rotation to North-up so user sees a familiar view
            try {
              _mapController.rotate(0);
            } catch (_) {}
          }
        },
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
