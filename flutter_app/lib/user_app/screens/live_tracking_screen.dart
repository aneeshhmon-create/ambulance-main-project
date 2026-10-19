// lib/user_app/screens/live_tracking_screen.dart
//
// Live map for the user: where the ambulance is, how far it is, and (once a
// hospital accepts) where the patient is being taken. Mirrors the driver app's
// navigation screen, read-only.
//
//  ┌──────────────────────────────────────────────────────────────┐
//  │  TrackingTopStrip (incident # / severity / expand)           │
//  ├──────────────────────────────────────────────────────────────┤
//  │                        OSM Map                               │
//  │   Status chip (top-centre)                                   │
//  │   ── Blue polyline  : ambulance → you (trimmed as it nears)  │
//  │   ── Teal polyline  : you → hospital                         │
//  │   ● Red pin   : you (incident)                               │
//  │   ● Teal badge: hospital (once assigned)                     │
//  │   ↑ Blue arrow: ambulance (moves smoothly, points its way)   │
//  │   [Legend]                                       [Recenter]  │
//  └──────────────────────────────────────────────────────────────┘
//
//  • Polls GET /incidents/{id}/tracking every 4 s; stops when the incident is
//    completed or the screen is closed, pauses while the app is paused.
//  • The ambulance → you route is requested from OSRM when the ambulance first
//    appears and again after it has moved ~60 m. You → hospital is fetched once
//    per assigned hospital. OSRM failure falls back to a dashed straight line.
//  • The camera fits everything when the ambulance first appears and when a
//    hospital is assigned; after that the user can pan and zoom freely and use
//    the Recenter button.
//  • If the ambulance cancels, the arrow and its route disappear and the chip
//    goes back to "Looking for an ambulance…".

import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:ambulance_app/user_app/config/routes.dart';
import 'package:ambulance_app/user_app/models/tracking.dart';
import 'package:ambulance_app/user_app/services/auth_service.dart';
import 'package:ambulance_app/user_app/services/routing_service.dart';
import 'package:ambulance_app/user_app/services/tracking_service.dart';
import 'package:ambulance_app/user_app/widgets/tracking_top_strip.dart';

/// Minimum ambulance movement (metres) before re-fetching its route.
const double _kRerouteThresholdM = 60.0;

/// Minimum movement (metres) before the arrow's heading is updated.
const double _kBearingThresholdM = 5.0;

const Color _kAmbulanceBlue = Color(0xFF1565C0);
const Color _kHospitalTeal = Color(0xFF00796B);

// ── helpers ──────────────────────────────────────────────────────────────────

/// Initial bearing (degrees, 0 = N, 90 = E) from [a] to [b].
double _calcBearing(LatLng a, LatLng b) {
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final dLng = (b.longitude - a.longitude) * pi / 180;
  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

/// Blends [current] bearing toward [next] (handles the 0/360 wrap).
double _smoothBearing(double current, double next) {
  var diff = next - current;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return (current + diff * 0.5 + 360) % 360;
}

/// Points of [points] from the vertex closest to [pos] onward, starting at
/// [pos] so the line begins exactly at the ambulance.
List<LatLng> _trimRoute(List<LatLng> points, LatLng pos) {
  if (points.length < 2) return [pos];
  var best = 0;
  var bestDistSq = double.infinity;
  for (var i = 0; i < points.length; i++) {
    final dx = points[i].latitude - pos.latitude;
    final dy = points[i].longitude - pos.longitude;
    final dSq = dx * dx + dy * dy;
    if (dSq < bestDistSq) {
      bestDistSq = dSq;
      best = i;
    }
  }
  if (best >= points.length - 1) return [pos, points.last];
  return [pos, ...points.sublist(best + 1)];
}

// ── widget ───────────────────────────────────────────────────────────────────

class LiveTrackingScreen extends StatefulWidget {
  final int incidentId;
  final TrackingService? trackingService;

  const LiveTrackingScreen({
    super.key,
    required this.incidentId,
    this.trackingService,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final TrackingService _service;

  // ── incident state ────────────────────────────────────────────────────────
  IncidentTracking? _incident;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  bool _pollingActive = false;
  bool _polling = false; // a request is in flight
  bool _leaving = false;

  // ── ambulance position (animated between polls) ───────────────────────────
  late final AnimationController _anim;
  int? _ambulanceId;
  LatLng? _ambFrom;
  LatLng? _ambTo;
  LatLng? _ambPos;
  double _bearing = 0;

  // ── routes ────────────────────────────────────────────────────────────────
  RouteResult? _toPatientRoute;
  List<LatLng>? _trimmedToPatient;
  bool _fetchingToPatient = false;
  LatLng? _lastRouteFetchPos;

  RouteResult? _toHospitalRoute;
  bool _fetchingToHospital = false;
  int? _lastHospitalId;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget.trackingService ?? TrackingService();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addListener(_onAnimTick);
    _startPolling(immediate: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _anim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_incident?.isCompleted != true) _startPolling(immediate: true);
      return;
    }
    // On web a window losing focus is reported as inactive/hidden; that is
    // not a real pause, so keep updating.
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopPolling();
    }
  }

  // ── polling ───────────────────────────────────────────────────────────────

  void _startPolling({bool immediate = false}) {
    _pollTimer?.cancel();
    _pollingActive = true;
    if (immediate) _poll();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  void _stopPolling() {
    _pollingActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    if (!_pollingActive || !mounted || _polling) return;
    _polling = true;
    try {
      final data = await _service.fetch(widget.incidentId);
      if (!mounted) return;
      _apply(data);
    } on TrackingException catch (e) {
      _handleError(e);
    } catch (e) {
      _handleError(TrackingException(e.toString()));
    } finally {
      _polling = false;
    }
  }

  void _handleError(TrackingException e) {
    if (!mounted) return;
    if (e.isUnauthorized) {
      _stopPolling();
      _signOutAndLeave();
      return;
    }
    if (e.isUnavailable) {
      _stopPolling();
      _showUnavailableDialog(e.message);
      return;
    }
    setState(() {
      _loading = false;
      _error = e.message;
    });
  }

  Future<void> _signOutAndLeave() async {
    await UserAuthService().signOut();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.root, (route) => false);
  }

  void _showUnavailableDialog(String message) {
    _leaving = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Tracking unavailable'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  // ── applying new data ─────────────────────────────────────────────────────

  void _apply(IncidentTracking d) {
    final firstLoad = _incident == null;
    setState(() {
      _incident = d;
      _loading = false;
      _error = null;
    });
    _applyAmbulance(d);
    _applyHospital(d);
    if (firstLoad) _fitAll();
    if (d.isCompleted) _stopPolling();
  }

  void _applyAmbulance(IncidentTracking d) {
    final amb = d.ambulance;
    final loc = amb?.location;

    // No ambulance (never assigned, or it cancelled): clear everything.
    if (amb == null || loc == null) {
      if (_ambPos != null || _toPatientRoute != null || _ambulanceId != null) {
        setState(() {
          _anim.stop();
          _ambulanceId = amb?.id;
          _ambFrom = _ambTo = _ambPos = null;
          _toPatientRoute = null;
          _trimmedToPatient = null;
          _lastRouteFetchPos = null;
        });
      }
      return;
    }

    // A different ambulance took over: start fresh at its position.
    if (_ambulanceId != amb.id || _ambTo == null) {
      final first = _ambTo == null || _ambulanceId != amb.id;
      setState(() {
        _anim.stop();
        _ambulanceId = amb.id;
        _ambFrom = _ambTo = _ambPos = loc;
        _toPatientRoute = null;
        _trimmedToPatient = null;
        _lastRouteFetchPos = null;
      });
      if (first) {
        _fetchToPatientRoute(loc);
        _fitAll();
      }
      return;
    }

    // Same ambulance moved: glide the arrow to the new position.
    final moved = const Distance().as(LengthUnit.Meter, _ambTo!, loc);
    if (moved < 1) return;
    if (moved >= _kBearingThresholdM) {
      _bearing = _smoothBearing(_bearing, _calcBearing(_ambTo!, loc));
    }
    _ambFrom = _ambPos ?? _ambTo;
    _ambTo = loc;
    _anim
      ..stop()
      ..reset()
      ..forward();
    _maybeReroute(loc);
  }

  void _onAnimTick() {
    if (_ambFrom == null || _ambTo == null) return;
    final t = Curves.linear.transform(_anim.value);
    final pos = LatLng(
      lerpDouble(_ambFrom!.latitude, _ambTo!.latitude, t)!,
      lerpDouble(_ambFrom!.longitude, _ambTo!.longitude, t)!,
    );
    setState(() {
      _ambPos = pos;
      if (_toPatientRoute != null) {
        _trimmedToPatient = _trimRoute(_toPatientRoute!.points, pos);
      }
    });
  }

  void _applyHospital(IncidentTracking d) {
    final hosp = d.assignedHospital;
    if (hosp == null) {
      if (_lastHospitalId != null || _toHospitalRoute != null) {
        setState(() {
          _lastHospitalId = null;
          _toHospitalRoute = null;
        });
      }
      return;
    }
    if (hosp.id == _lastHospitalId) return;
    _lastHospitalId = hosp.id;
    _fetchToHospitalRoute(d, hosp);
  }

  // ── routing ───────────────────────────────────────────────────────────────

  void _maybeReroute(LatLng pos) {
    if (_fetchingToPatient) return;
    final last = _lastRouteFetchPos;
    if (last != null &&
        const Distance().as(LengthUnit.Meter, last, pos) <
            _kRerouteThresholdM) {
      return;
    }
    _fetchToPatientRoute(pos);
  }

  Future<void> _fetchToPatientRoute(LatLng from) async {
    final inc = _incident;
    if (inc == null || _fetchingToPatient) return;
    setState(() => _fetchingToPatient = true);
    _lastRouteFetchPos = from;
    final ambId = _ambulanceId;
    final result =
        await RoutingService.getRoute(origin: from, destination: inc.location);
    if (!mounted) return;
    setState(() {
      _fetchingToPatient = false;
      // Ignore a result for an ambulance that has since gone away or changed.
      if (_ambulanceId != ambId || _ambTo == null) return;
      _toPatientRoute = result;
      _trimmedToPatient = _ambPos != null
          ? _trimRoute(result.points, _ambPos!)
          : result.points;
    });
  }

  Future<void> _fetchToHospitalRoute(
      IncidentTracking d, TrackingHospital hosp) async {
    setState(() => _fetchingToHospital = true);
    final result = await RoutingService.getRoute(
      origin: d.location,
      destination: hosp.location,
    );
    if (!mounted) return;
    if (_lastHospitalId != hosp.id) {
      // Hospital changed or was cleared while routing.
      setState(() => _fetchingToHospital = false);
      return;
    }
    setState(() {
      _toHospitalRoute = result;
      _fetchingToHospital = false;
    });
    _fitAll();
  }

  // ── camera ────────────────────────────────────────────────────────────────

  void _fitAll() {
    final inc = _incident;
    if (inc == null) return;
    final pts = <LatLng>[inc.location];
    if (_ambPos != null) pts.add(_ambPos!);
    if (inc.assignedHospital != null) pts.add(inc.assignedHospital!.location);
    try {
      if (pts.length == 1) {
        _mapController.move(pts.first, 15.0);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.all(70),
          ),
        );
      }
    } catch (_) {
      // Map not built yet (first load); initialCenter covers it.
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: cs.primary),
                    const SizedBox(height: 16),
                    Text('Loading incident #${widget.incidentId}…',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            : _incident == null
                ? _buildFailed(cs)
                : _buildMapView(cs),
      ),
    );
  }

  Widget _buildFailed(ColorScheme cs) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(_error ?? 'Could not load tracking.',
                style: TextStyle(color: cs.onSurface)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                setState(() => _loading = true);
                _poll();
              },
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      );

  Widget _buildMapView(ColorScheme cs) {
    final inc = _incident!;
    return Column(
      children: [
        TrackingTopStrip(
          incident: inc,
          onBack: () {
            if (!_leaving) Navigator.of(context).maybePop();
          },
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: cs.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Icon(Icons.wifi_off_rounded,
                  size: 16, color: cs.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sync issue: $_error',
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
                onPressed: _poll,
                child: Text('Retry',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        Expanded(
          child: Stack(
            children: [
              _buildMap(inc),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _buildStatusChip(Theme.of(context), cs, inc),
                ),
              ),
              Positioned(
                bottom: 28,
                left: 14,
                child: _buildLegend(cs, inc),
              ),
              Positioned(
                bottom: 28,
                right: 14,
                child: FloatingActionButton.small(
                  heroTag: 'user_recenter_fab',
                  backgroundColor: cs.surface,
                  foregroundColor: cs.primary,
                  elevation: 4,
                  tooltip: 'Recenter',
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

  // ── status chip ───────────────────────────────────────────────────────────

  Widget _buildStatusChip(ThemeData t, ColorScheme cs, IncidentTracking inc) {
    final hosp = inc.assignedHospital;
    final rows = <Widget>[
      _chipRow(
        t,
        cs,
        icon: Icons.airport_shuttle_rounded,
        color: cs.primary,
        text: _ambulanceText(inc),
        busy: _fetchingToPatient && _toPatientRoute == null,
      ),
      if (hosp != null)
        _chipRow(
          t,
          cs,
          icon: Icons.local_hospital_rounded,
          color: _kHospitalTeal,
          text: _hospitalText(hosp),
          busy: _fetchingToHospital && _toHospitalRoute == null,
        ),
    ];
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: (hosp != null ? _kHospitalTeal : cs.primary)
                .withValues(alpha: 0.5),
            width: 1.3,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipRow(
    ThemeData t,
    ColorScheme cs, {
    required IconData icon,
    required Color color,
    required String text,
    required bool busy,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: t.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (busy) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
          ),
        ],
      ],
    );
  }

  String _ambulanceText(IncidentTracking inc) {
    if (inc.isCompleted) return 'Completed';
    final amb = inc.ambulance;
    if (amb == null) return 'Looking for an ambulance…';
    if (amb.location == null) {
      return 'Ambulance ${amb.registrationNumber} assigned…';
    }
    final r = _toPatientRoute;
    if (r == null) return 'Ambulance ${amb.registrationNumber} on the way…';
    final km = r.distanceKm.toStringAsFixed(1);
    final min = r.durationMinutes.ceil();
    return r.isFallback
        ? 'Ambulance ${amb.registrationNumber}  ~$km km away'
        : 'Ambulance ${amb.registrationNumber}  $km km · $min min away';
  }

  String _hospitalText(TrackingHospital h) {
    final r = _toHospitalRoute;
    if (r == null) return 'Hospital: ${h.name}';
    final km = r.distanceKm.toStringAsFixed(1);
    final min = r.durationMinutes.ceil();
    return r.isFallback
        ? '${h.name}  ~$km km'
        : '${h.name}  $km km · $min min';
  }

  // ── legend ────────────────────────────────────────────────────────────────

  Widget _buildLegend(ColorScheme cs, IncidentTracking inc) {
    final rows = <Widget>[
      if (_ambPos != null) _legendRow(_kAmbulanceBlue, 'Ambulance → You'),
      if (inc.assignedHospital != null) _legendRow(_kHospitalTeal, 'You → Hospital'),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
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
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            rows[i],
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
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      );

  // ── map ───────────────────────────────────────────────────────────────────

  Widget _buildMap(IncidentTracking inc) {
    final hosp = inc.assignedHospital;

    final markers = <Marker>[
      // You — red pin
      Marker(
        point: inc.location,
        width: 44,
        height: 44,
        child: const Icon(Icons.location_on_rounded,
            color: Color(0xFFD32F2F), size: 42),
      ),
      // Hospital — teal badge
      if (hosp != null)
        Marker(
          point: hosp.location,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _kHospitalTeal, width: 2.3),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 5,
                    offset: Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.local_hospital_rounded,
                color: _kHospitalTeal, size: 26),
          ),
        ),
      // Ambulance — blue arrow
      if (_ambPos != null)
        Marker(
          point: _ambPos!,
          width: 52,
          height: 52,
          child: Transform.rotate(
            angle: _bearing * pi / 180,
            child: Container(
              decoration: BoxDecoration(
                color: _kAmbulanceBlue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _kAmbulanceBlue.withValues(alpha: 0.45),
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
              child: const Icon(Icons.navigation_rounded,
                  color: Colors.white, size: 28),
            ),
          ),
        ),
    ];

    final polylines = <Polyline>[];
    final leg1 = _trimmedToPatient ?? _toPatientRoute?.points;
    if (_ambPos != null && leg1 != null && leg1.length >= 2) {
      polylines.add(_line(leg1, _kAmbulanceBlue,
          fallback: _toPatientRoute?.isFallback ?? true));
    }
    if (hosp != null &&
        _toHospitalRoute != null &&
        _toHospitalRoute!.points.length >= 2) {
      polylines.add(_line(_toHospitalRoute!.points, _kHospitalTeal,
          fallback: _toHospitalRoute!.isFallback));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: inc.location,
        initialZoom: 14.5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.team19.ambulance.user',
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

  Polyline _line(List<LatLng> points, Color color, {required bool fallback}) {
    return Polyline(
      points: points,
      strokeWidth: fallback ? 3.5 : 5.0,
      color: fallback ? color.withValues(alpha: 0.55) : color,
      pattern: fallback
          ? StrokePattern.dashed(segments: const [12, 8])
          : const StrokePattern.solid(),
      borderStrokeWidth: 1.5,
      borderColor: Colors.white.withValues(alpha: 0.3),
    );
  }
}
