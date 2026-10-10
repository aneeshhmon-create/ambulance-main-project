import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/incident.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/user_storage.dart';

// ---------------------------------------------------------------------------
// State enum
// ---------------------------------------------------------------------------

enum SubmitState {
  gettingLocation,
  locationServicesOff,
  locationDenied,
  locationPermanentlyDenied,
  uploading,
  success,
  error,
}

// ---------------------------------------------------------------------------
// SubmitController
// ---------------------------------------------------------------------------

/// Manages GPS location acquisition and incident report upload to the backend.
class SubmitController extends ChangeNotifier {
  SubmitController({
    required this.audioPath,
    LocationService? locationService,
    ApiService? apiService,
    UserStorage? userStorage,
    User? currentUser,
    Future<void> Function(String path)? deleteFile,
  })  : _locationService = locationService ?? const GeolocatorLocationService(),
        _apiService = apiService ?? ApiService(),
        _userStorage = userStorage ?? UserStorage(),
        _currentUser = currentUser,
        _deleteFile = deleteFile ?? _defaultDeleteFile;

  final String audioPath;
  final LocationService _locationService;
  final ApiService _apiService;
  final UserStorage _userStorage;
  final Future<void> Function(String path) _deleteFile;

  User? _currentUser;
  UserLocation? _location;
  Incident? _incident;
  String _errorMessage = '';
  SubmitState _state = SubmitState.gettingLocation;
  bool _isBusy = false;

  // ── Getters ────────────────────────────────────────────────────────────────

  SubmitState get state => _state;
  UserLocation? get location => _location;
  Incident? get incident => _incident;
  String get errorMessage => _errorMessage;
  bool get isBusy => _isBusy;
  LocationService get locationService => _locationService;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initiates the full submission workflow: get location, then upload.
  Future<void> submit() async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      // Step 1: Ensure user is loaded
      _currentUser ??= await _userStorage.loadUser();

      // Step 2: Get Location (if not already acquired)
      if (_location == null) {
        _setState(SubmitState.gettingLocation);
        try {
          _location = await _locationService.getCurrentLocation();
        } on LocationServiceDisabledException {
          _setState(SubmitState.locationServicesOff);
          return;
        } on LocationPermissionDeniedException {
          _setState(SubmitState.locationDenied);
          return;
        } on LocationPermissionPermanentlyDeniedException {
          _setState(SubmitState.locationPermanentlyDenied);
          return;
        } on LocationException catch (e) {
          _errorMessage = e.message;
          _setState(SubmitState.error);
          return;
        } catch (e) {
          _errorMessage = 'Location error: $e';
          _setState(SubmitState.error);
          return;
        }
      }

      // Step 3: Upload Report
      await _uploadReport();
    } finally {
      _isBusy = false;
    }
  }

  /// Retries from the last failed point.
  ///
  /// If location was already captured, it does not re-query GPS and proceeds
  /// directly to uploading. Audio file is preserved.
  Future<void> retry() async {
    if (_isBusy) return;

    if (_location != null &&
        (_state == SubmitState.error || _state == SubmitState.uploading)) {
      _isBusy = true;
      try {
        await _uploadReport();
      } finally {
        _isBusy = false;
      }
    } else {
      // Location failed or was not obtained yet — restart submit()
      await submit();
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _uploadReport() async {
    if (_location == null) {
      _errorMessage = 'Location is required to dispatch help.';
      _setState(SubmitState.error);
      return;
    }

    _setState(SubmitState.uploading);

    try {
      final res = await _apiService.submitIncident(
        audioPath: audioPath,
        userId: _currentUser?.id,
        lat: _location!.latitude,
        lng: _location!.longitude,
      );

      _incident = res;
      _setState(SubmitState.success);

      // Clean up audio file ONLY after confirmed success
      await _deleteFile(audioPath);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _setState(SubmitState.error);
    } catch (e) {
      _errorMessage = 'Submission failed: $e';
      _setState(SubmitState.error);
    }
  }

  void _setState(SubmitState s) {
    _state = s;
    notifyListeners();
  }

  static Future<void> _defaultDeleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
