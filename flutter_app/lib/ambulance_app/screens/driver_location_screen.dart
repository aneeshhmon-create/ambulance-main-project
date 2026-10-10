import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/ambulance_service.dart';

// How often to push the location (seconds).
const int _kIntervalSeconds = 5;

enum _SharingStatus {
  idle,
  sharing,
  permissionDenied,
  gpsDisabled,
  connectionError,
}

class DriverLocationScreen extends StatefulWidget {
  const DriverLocationScreen({super.key});

  @override
  State<DriverLocationScreen> createState() => _DriverLocationScreenState();
}

class _DriverLocationScreenState extends State<DriverLocationScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _idController = TextEditingController();

  _SharingStatus _status = _SharingStatus.idle;
  double? _lat;
  double? _lng;
  String? _lastError;
  DateTime? _lastUpdated;
  Timer? _timer;
  bool _isSending = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<bool> _checkPermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setStatus(_SharingStatus.gpsDisabled);
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _setStatus(_SharingStatus.permissionDenied);
      return false;
    }
    return true;
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } on LocationServiceDisabledException {
      _setStatus(_SharingStatus.gpsDisabled);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendLocation(
      String ambulanceId, double lat, double lng) async {
    try {
      await AmbulanceService.updateLocation(
        ambulanceId: ambulanceId,
        lat: lat,
        lng: lng,
      );
      if (_status == _SharingStatus.connectionError) {
        _setStatus(_SharingStatus.sharing);
      }
      setState(() => _lastError = null);
    } catch (e) {
      setState(() => _lastError = e.toString());
      _setStatus(_SharingStatus.connectionError);
    }
  }

  Future<void> _startSharing() async {
    final ambulanceId = _idController.text.trim();
    if (ambulanceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an ambulance ID first.')),
      );
      return;
    }
    final ok = await _checkPermissions();
    if (!ok) return;
    _setStatus(_SharingStatus.sharing);
    await _tick(ambulanceId);
    _timer = Timer.periodic(
      const Duration(seconds: _kIntervalSeconds),
      (_) => _tick(ambulanceId),
    );
  }

  Future<void> _tick(String ambulanceId) async {
    if (_isSending) return;
    _isSending = true;
    try {
      final position = await _getCurrentPosition();
      if (position == null) {
        _isSending = false;
        return;
      }
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _lastUpdated = DateTime.now();
      });
      await _sendLocation(ambulanceId, position.latitude, position.longitude);
    } finally {
      _isSending = false;
    }
  }

  void _stopSharing() {
    _timer?.cancel();
    _timer = null;
    _setStatus(_SharingStatus.idle);
    setState(() => _lastError = null);
  }

  void _setStatus(_SharingStatus status) {
    if (mounted) setState(() => _status = status);
  }

  (IconData, String, Color) _statusInfo() {
    return switch (_status) {
      _SharingStatus.idle => (
          Icons.location_off_outlined,
          'Not sharing',
          const Color(0xFF6B7280),
        ),
      _SharingStatus.sharing => (
          Icons.location_on,
          'Sharing location...',
          const Color(0xFF10B981),
        ),
      _SharingStatus.permissionDenied => (
          Icons.block,
          'Permission denied — enable in Settings',
          const Color(0xFFEF4444),
        ),
      _SharingStatus.gpsDisabled => (
          Icons.gps_off,
          'GPS is disabled on this device',
          const Color(0xFFF59E0B),
        ),
      _SharingStatus.connectionError => (
          Icons.wifi_off_rounded,
          'Connection error, retrying...',
          const Color(0xFFEF4444),
        ),
    };
  }

  Widget _buildStatusBadge() {
    final (icon, label, color) = _statusInfo();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_status == _SharingStatus.sharing)
            ScaleTransition(
              scale: _pulseAnimation,
              child: Icon(icon, color: color, size: 18),
            )
          else
            Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordCard(String label, double? value) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2535),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value != null
                ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                value != null ? value.toStringAsFixed(6) : 'no data',
                key: ValueKey(value?.toStringAsFixed(6)),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSharing = _status == _SharingStatus.sharing;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1623),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_hospital_rounded,
                      color: Color(0xFFEF4444),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Driver Location',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Live GPS sharing',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 36),

              // Ambulance ID input
              Text(
                'AMBULANCE ID',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _idController,
                enabled: !isSharing,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'e.g. amb-001',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                  filled: true,
                  fillColor: const Color(0xFF1E2535),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF3B82F6),
                      width: 1.5,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.badge_outlined,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Status badge
              Center(child: _buildStatusBadge()),

              // Connection error detail
              if (_lastError != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _lastError!,
                      style:
                          const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Coordinates display
              Text(
                'CURRENT POSITION',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildCoordCard('LATITUDE', _lat),
                  const SizedBox(width: 12),
                  _buildCoordCard('LONGITUDE', _lng),
                ],
              ),

              if (_lastUpdated != null) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Last updated: ${_formatTime(_lastUpdated!)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 40),

              // Action button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: isSharing
                      ? OutlinedButton.icon(
                          key: const ValueKey('stop'),
                          onPressed: _stopSharing,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text(
                            'Stop Sharing',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(
                                color: Color(0xFFEF4444), width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        )
                      : ElevatedButton.icon(
                          key: const ValueKey('start'),
                          onPressed: _startSharing,
                          icon: const Icon(Icons.my_location_rounded),
                          label: const Text(
                            'Start Sharing Location',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // GPS disabled helper
              if (_status == _SharingStatus.gpsDisabled)
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      await Geolocator.openLocationSettings();
                    },
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Open Location Settings'),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFF59E0B)),
                  ),
                ),

              // Permission denied helper
              if (_status == _SharingStatus.permissionDenied)
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      await Geolocator.openAppSettings();
                    },
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Open App Settings'),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444)),
                  ),
                ),

              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Updates every $_kIntervalSeconds s  •  PATCH $kAmbulanceBaseUrl/ambulances/{id}/location',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
