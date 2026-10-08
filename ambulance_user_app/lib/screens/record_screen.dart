import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/recording_controller.dart';
import '../services/audio_recorder_service.dart';

// ---------------------------------------------------------------------------
// RecordScreen — route '/report'
// ---------------------------------------------------------------------------

/// Voice-recording screen.
///
/// Owns a [RecordingController] (with the real [RecordPackageRecorder]) and
/// maps every [RecordingState] to a distinct UI.  It also handles lifecycle
/// edge-cases: stopping the recorder when the screen is popped mid-recording.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, AudioRecorderService? recorderService})
      : _recorderService = recorderService;

  final AudioRecorderService? _recorderService;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with WidgetsBindingObserver {
  late final RecordingController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = RecordingController(
      recorderService: widget._recorderService ?? RecordPackageRecorder(),
    )..addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  // Stop recording cleanly when the app goes to background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _controller.state == RecordingState.recording) {
      _controller.stopRecording();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onStateChange)
      ..dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (_controller.state == RecordingState.recording) {
      await _controller.stopRecording();
    }
    return true;
  }

  void _navigateToSubmit() {
    Navigator.of(context).pushNamed(
      '/submit',
      arguments: _controller.recordedPath,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final canLeave = await _onWillPop();
          if (canLeave && context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Report Emergency'),
          backgroundColor: Colors.red[700],
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final state = _controller.state;

    if (state == RecordingState.recorded) {
      return _PlaybackView(
        path: _controller.recordedPath!,
        onReRecord: _controller.reRecord,
        onContinue: _navigateToSubmit,
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusMessage(state: state, elapsed: _controller.elapsed),
        const SizedBox(height: 48),
        _MicButton(
          state: state,
          elapsed: _controller.elapsed,
          onStart: _controller.startRecording,
          onStop: _controller.stopRecording,
        ),
        const SizedBox(height: 48),
        _ActionRow(
          state: state,
          onRetry: _controller.startRecording,
          onOpenSettings: openAppSettings,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

/// Contextual text that tells the user what to do or what went wrong.
class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.state, required this.elapsed});

  final RecordingState state;
  final int elapsed;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (state) {
      RecordingState.idle => (
          'Tap the mic and describe the emergency',
          Colors.black87
        ),
      RecordingState.recording => (
          _fmt(elapsed),
          Colors.red[700]!,
        ),
      RecordingState.tooShort => (
          'Recording too short — please try again (min 2 s)',
          Colors.orange[800]!
        ),
      RecordingState.permissionDenied => (
          'Microphone permission was denied.\nPlease tap "Try Again" to re-prompt.',
          Colors.red[800]!,
        ),
      RecordingState.permissionPermanentlyDenied => (
          'Microphone access is permanently blocked.\n'
              'Open Settings and enable the Microphone permission for this app.',
          Colors.red[800]!,
        ),
      RecordingState.error => (
          'Something went wrong with the recorder.',
          Colors.red[800]!
        ),
      RecordingState.recorded => ('', Colors.transparent),
    };

    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.5,
      ),
    );
  }

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// The large animated mic button.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.state,
    required this.elapsed,
    required this.onStart,
    required this.onStop,
  });

  final RecordingState state;
  final int elapsed;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isRecording = state == RecordingState.recording;
    final isActive = [
      RecordingState.idle,
      RecordingState.recording,
      RecordingState.tooShort,
      RecordingState.error,
    ].contains(state);

    return Center(
      child: GestureDetector(
        onTap: isActive ? (isRecording ? onStop : onStart) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isRecording ? Colors.red[700] : Colors.red[100],
            boxShadow: [
              if (isRecording)
                BoxShadow(
                  color: Colors.red.withAlpha(100),
                  blurRadius: 30,
                  spreadRadius: 8,
                ),
            ],
          ),
          child: Icon(
            isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            size: 64,
            color: isRecording ? Colors.white : Colors.red[700],
          ),
        ),
      ),
    );
  }
}

/// "Try Again" / "Open Settings" buttons shown only when relevant.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.state,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final RecordingState state;
  final VoidCallback onRetry;
  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (state == RecordingState.permissionDenied) {
      return Center(
        child: FilledButton.tonal(
          onPressed: onRetry,
          child: const Text('Try Again'),
        ),
      );
    }

    if (state == RecordingState.permissionPermanentlyDenied) {
      return Center(
        child: FilledButton(
          onPressed: () => onOpenSettings(),
          style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
          child: const Text('Open Settings'),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Playback view — shown after a successful recording
// ---------------------------------------------------------------------------

class _PlaybackView extends StatefulWidget {
  const _PlaybackView({
    required this.path,
    required this.onReRecord,
    required this.onContinue,
  });

  final String path;
  final Future<void> Function() onReRecord;
  final VoidCallback onContinue;

  @override
  State<_PlaybackView> createState() => _PlaybackViewState();
}

class _PlaybackViewState extends State<_PlaybackView> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  StreamSubscription<PlayerState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(widget.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == PlayerState.playing;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 80),
        const SizedBox(height: 16),
        const Text(
          'Recording saved!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),

        // Play / Pause preview
        Center(
          child: IconButton.filled(
            icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            iconSize: 48,
            style: IconButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
              minimumSize: const Size(80, 80),
            ),
            onPressed: _togglePlayback,
            tooltip: isPlaying ? 'Pause' : 'Play preview',
          ),
        ),
        const SizedBox(height: 48),

        // Re-record
        OutlinedButton.icon(
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Re-record'),
          onPressed: () async {
            await _player.stop();
            await widget.onReRecord();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red[700],
            side: BorderSide(color: Colors.red[700]!),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 16),

        // Continue
        FilledButton.icon(
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Continue'),
          onPressed: widget.onContinue,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
