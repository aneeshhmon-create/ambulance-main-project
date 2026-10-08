import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/audio_recorder_service.dart';

// ---------------------------------------------------------------------------
// State enum
// ---------------------------------------------------------------------------

/// All states the recording flow can be in.
enum RecordingState {
  /// No recording in progress, no file ready.
  idle,

  /// Mic permission was denied this session (can retry via the prompt).
  permissionDenied,

  /// Mic permission was permanently denied (user must open app settings).
  permissionPermanentlyDenied,

  /// Actively recording.
  recording,

  /// Recording finished and accepted (≥ [RecordingController.minDuration]).
  recorded,

  /// Recording was stopped too early (< [RecordingController.minDuration]).
  tooShort,

  /// An unexpected recorder error occurred.
  error,
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Owns all microphone-recording business logic.
///
/// Responsibilities:
/// - Request/check microphone permission.
/// - Manage the `record` package via [AudioRecorderService].
/// - Drive an elapsed-seconds ticker while recording.
/// - Enforce minimum (2 s) and maximum (60 s) durations.
/// - Expose [state], [elapsed], [recordedPath], [errorMessage] for the UI.
///
/// The controller is pure Dart (no Flutter widgets), making it straightforward
/// to test with a [FakeAudioRecorderService] and `fake_async`.
class RecordingController extends ChangeNotifier {
  RecordingController({
    required AudioRecorderService recorderService,
    /// Injected so tests can control `getTempDirectory`.
    Future<Directory> Function()? getTempDir,
    /// Injected so tests can mock permission status without platform channels.
    Future<PermissionStatus> Function()? checkAndRequestPermission,
    /// Injected so tests can mock file deletion without native async I/O.
    Future<void> Function(String path)? deleteFile,
  })  : _recorder = recorderService,
        _getTempDir = getTempDir ?? getTemporaryDirectory,
        _checkAndRequestPermission =
            checkAndRequestPermission ?? _defaultCheckAndRequestPermission,
        _deleteFileFn = deleteFile ?? _defaultDeleteFile;

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Minimum acceptable recording length in seconds.
  static const int minDuration = 2;

  /// Maximum recording length in seconds; auto-stops at this limit.
  static const int maxDuration = 60;

  // ── Dependencies ───────────────────────────────────────────────────────────

  final AudioRecorderService _recorder;
  final Future<Directory> Function() _getTempDir;
  final Future<PermissionStatus> Function() _checkAndRequestPermission;
  final Future<void> Function(String path) _deleteFileFn;

  // ── State ──────────────────────────────────────────────────────────────────

  RecordingState _state = RecordingState.idle;
  int _elapsed = 0;
  String? _recordedPath;
  String _errorMessage = '';

  Timer? _ticker;

  // ── Public getters ─────────────────────────────────────────────────────────

  RecordingState get state => _state;
  int get elapsed => _elapsed;

  /// Absolute path to the accepted recording. Non-null only in [RecordingState.recorded].
  String? get recordedPath => _recordedPath;

  /// Human-readable error description. Non-empty only in [RecordingState.error].
  String get errorMessage => _errorMessage;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Checks/requests the microphone permission, then starts recording.
  ///
  /// Transitions:
  /// - granted → recording
  /// - denied  → permissionDenied
  /// - permanentlyDenied / restricted → permissionPermanentlyDenied
  Future<void> startRecording() async {
    if (_state == RecordingState.recording) return;

    // ── Permission check ──────────────────────────────────────────────────
    PermissionStatus status = await _checkAndRequestPermission();

    if (status.isPermanentlyDenied || status.isRestricted) {
      _setState(RecordingState.permissionPermanentlyDenied);
      return;
    }

    if (!status.isGranted) {
      _setState(RecordingState.permissionDenied);
      return;
    }

    // ── Start recorder ────────────────────────────────────────────────────
    try {
      final dir = await _getTempDir();
      final path =
          '${dir.path}/report_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(path);

      _elapsed = 0;
      _recordedPath = path; // tentative — cleared if tooShort
      _startTicker();
      _setState(RecordingState.recording);
    } catch (e) {
      _errorMessage = e.toString();
      _setState(RecordingState.error);
    }
  }

  /// Stops an active recording.
  ///
  /// If elapsed < [minDuration]: state → tooShort, file deleted.
  /// Otherwise: state → recorded.
  Future<void> stopRecording() async {
    if (_state != RecordingState.recording) return;
    _stopTicker();

    try {
      await _recorder.stop();
    } catch (e) {
      _errorMessage = e.toString();
      _recordedPath = null;
      _setState(RecordingState.error);
      return;
    }

    if (_elapsed < minDuration) {
      await _deleteFile(_recordedPath);
      _recordedPath = null;
      _setState(RecordingState.tooShort);
    } else {
      _setState(RecordingState.recorded);
    }
  }

  /// Deletes the previous recording and returns to [RecordingState.idle].
  Future<void> reRecord() async {
    if (_state == RecordingState.recording) {
      await stopRecording();
    }
    await _deleteFile(_recordedPath);
    _recordedPath = null;
    _elapsed = 0;
    _setState(RecordingState.idle);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    // Stop any active recording but do NOT delete an already-accepted file.
    if (_state == RecordingState.recording) {
      _stopTicker();
      try {
        await _recorder.stop();
        // If we were recording when disposed, treat it as too short / discard.
        if (_elapsed < minDuration) {
          await _deleteFile(_recordedPath);
          _recordedPath = null;
        }
        // else: leave the file; the UI that started us may still need it.
      } catch (_) {}
    }
    await _recorder.dispose();
    super.dispose();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _setState(RecordingState s) {
    _state = s;
    notifyListeners();
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed++;
      notifyListeners();
      if (_elapsed >= maxDuration) {
        stopRecording();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null) return;
    await _deleteFileFn(path);
  }

  static Future<void> _defaultDeleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<PermissionStatus> _defaultCheckAndRequestPermission() async {
    PermissionStatus status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    return status;
  }
}

