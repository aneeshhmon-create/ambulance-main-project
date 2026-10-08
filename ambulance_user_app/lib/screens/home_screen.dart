import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../config/routes.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/user_storage.dart';

enum _ServerHealthStatus { checking, connected, unreachable }

class DemoPreset {
  const DemoPreset({
    required this.label,
    required this.emergencyType,
    required this.departmentNeeded,
    required this.severity,
    required this.victims,
    required this.symptoms,
  });

  final String label;
  final String emergencyType;
  final String departmentNeeded;
  final String severity;
  final int victims;
  final List<String> symptoms;
}

const List<DemoPreset> _demoPresets = [
  DemoPreset(
    label: 'Road accident - critical',
    emergencyType: 'Road accident',
    departmentNeeded: 'Trauma',
    severity: 'critical',
    victims: 2,
    symptoms: ['Severe bleeding', 'Head trauma'],
  ),
  DemoPreset(
    label: 'Chest pain - cardiac',
    emergencyType: 'Chest pain',
    departmentNeeded: 'Cardiology',
    severity: 'high',
    victims: 1,
    symptoms: ['Chest pressure', 'Shortness of breath'],
  ),
  DemoPreset(
    label: 'Child high fever - paediatric',
    emergencyType: 'Child high fever',
    departmentNeeded: 'Pediatrics',
    severity: 'medium',
    victims: 1,
    symptoms: ['High fever', 'Convulsions'],
  ),
  DemoPreset(
    label: 'Mild fever - general',
    emergencyType: 'Mild fever',
    departmentNeeded: 'General Medicine',
    severity: 'low',
    victims: 1,
    symptoms: ['Mild fever', 'Headache'],
  ),
];

/// Home screen — main patient dashboard with server indicator and demo mode.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.user,
    this.apiService,
    this.userStorage,
    this.locationService,
  });

  final User? user;
  final ApiService? apiService;
  final UserStorage? userStorage;
  final LocationService? locationService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiService _api;
  late final UserStorage _storage;
  late final LocationService _locationService;

  User? _currentUser;
  bool _isLoadingUser = true;

  // Server health indicator
  _ServerHealthStatus _serverStatus = _ServerHealthStatus.checking;

  // Demo mode state (in-memory only, never persisted)
  bool _isDemoMode = false;
  int _titleTapCount = 0;
  DateTime? _lastTitleTap;
  bool _isSubmittingPreset = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
    _storage = widget.userStorage ?? UserStorage();
    _locationService = widget.locationService ?? const GeolocatorLocationService();

    _initUser();
    _checkServerStatus();
  }

  Future<void> _initUser() async {
    if (widget.user != null) {
      setState(() {
        _currentUser = widget.user;
        _isLoadingUser = false;
      });
      return;
    }

    final loaded = await _storage.loadUser();
    if (mounted) {
      setState(() {
        _currentUser = loaded;
        _isLoadingUser = false;
      });
    }
  }

  Future<void> _checkServerStatus() async {
    setState(() => _serverStatus = _ServerHealthStatus.checking);
    try {
      await _api.checkHealth().timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() => _serverStatus = _ServerHealthStatus.connected);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _serverStatus = _ServerHealthStatus.unreachable);
      }
    }
  }

  void _onTitleTapped() {
    final now = DateTime.now();
    if (_lastTitleTap == null || now.difference(_lastTitleTap!) > const Duration(seconds: 2)) {
      _titleTapCount = 1;
    } else {
      _titleTapCount++;
    }
    _lastTitleTap = now;

    if (_titleTapCount >= 5) {
      _titleTapCount = 0;
      setState(() {
        _isDemoMode = !_isDemoMode;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isDemoMode ? 'DEMO MODE ENABLED' : 'Demo mode disabled'),
          duration: const Duration(seconds: 2),
          backgroundColor: _isDemoMode ? Colors.orange[900] : Colors.grey[800],
        ),
      );
    }
  }

  Future<void> _switchUser() async {
    await _storage.clearUser();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.register, (route) => false);
  }

  Future<void> _submitPreset(DemoPreset preset) async {
    if (_isSubmittingPreset) return;
    setState(() => _isSubmittingPreset = true);

    try {
      double lat;
      double lng;
      bool usedFallbackLocation = false;

      try {
        final loc = await _locationService.getCurrentLocation();
        lat = loc.latitude;
        lng = loc.longitude;
      } catch (e) {
        lat = ApiConfig.demoLat;
        lng = ApiConfig.demoLng;
        usedFallbackLocation = true;
      }

      if (usedFallbackLocation && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS unavailable — using demo coordinates ($lat, $lng)'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.amber[900],
          ),
        );
      }

      final incident = await _api.submitManualIncident(
        lat: lat,
        lng: lng,
        userId: _currentUser?.id,
        emergencyType: preset.emergencyType,
        severity: preset.severity,
        symptoms: preset.symptoms,
        victims: preset.victims,
        departmentNeeded: preset.departmentNeeded,
      );

      final displayIncident = incident.copyWith(transcript: preset.label);

      if (mounted) {
        Navigator.of(context).pushNamed(
          AppRoutes.result,
          arguments: displayIncident,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preset dispatch failed: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingPreset = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final displayName = _currentUser?.name ?? 'User';
    final displayPhone = _currentUser?.phone ?? '';

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTapped,
          child: const Text('Emergency Ambulance'),
        ),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Bar: Server indicator & greeting ───────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Hi, $displayName',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                    ),
                  ),
                  _buildServerStatusIndicator(),
                ],
              ),
              if (displayPhone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Mobile: $displayPhone',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                ),
              ],
              const SizedBox(height: 20),

              // ── DEMO MODE Banner ───────────────────────────────────────────
              if (_isDemoMode) _buildDemoModeBanner(),

              const SizedBox(height: 16),

              // ── Report Emergency Card ──────────────────────────────────────
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.emergency_share_rounded,
                        color: Colors.red,
                        size: 72,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Need Immediate Assistance?',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Dispatch an ambulance and find nearest hospital bed allocation with one tap.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed(AppRoutes.report);
                          },
                          icon: const Icon(Icons.warning_amber_rounded, size: 28),
                          label: const Text(
                            'Report Emergency',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Quick Demo Reports Panel ───────────────────────────────────
              if (_isDemoMode) ...[
                const SizedBox(height: 24),
                _buildDemoPanel(),
              ],

              const SizedBox(height: 16),

              // ── Switch user button ─────────────────────────────────────────
              Center(
                child: TextButton.icon(
                  onPressed: _switchUser,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Switch user'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerStatusIndicator() {
    final (dotColor, label) = switch (_serverStatus) {
      _ServerHealthStatus.connected => (Colors.green, 'Server connected'),
      _ServerHealthStatus.unreachable => (Colors.red, 'Server unreachable'),
      _ServerHealthStatus.checking => (Colors.amber, 'Checking...'),
    };

    return InkWell(
      key: const ValueKey('server_status_indicator'),
      onTap: _checkServerStatus,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoModeBanner() {
    return Container(
      key: const ValueKey('demo_mode_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Colors.orange.shade400, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange[900], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEMO MODE ACTIVE',
                  style: TextStyle(
                    color: Colors.orange[900],
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Using simulated reports & safety net fallback.',
                  style: TextStyle(color: Colors.orange[950], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoPanel() {
    return Container(
      key: const ValueKey('demo_reports_panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: Colors.amber[800], size: 20),
              const SizedBox(width: 6),
              const Text(
                'Quick demo reports',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Instant dispatch presets (bypasses microphone)',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          if (_isSubmittingPreset)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(color: Colors.red),
              ),
            )
          else
            ..._demoPresets.map((preset) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _submitPreset(preset),
                    icon: Icon(
                      Icons.play_circle_outline_rounded,
                      size: 20,
                      color: Colors.red[700],
                    ),
                    label: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        preset.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
