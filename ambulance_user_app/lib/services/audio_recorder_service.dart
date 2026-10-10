import 'package:record/record.dart';

/// Abstract API for microphone recording.
///
/// The concrete [RecordPackageRecorder] wraps the `record` package.
/// Tests inject a [FakeAudioRecorderService] so the controller never touches
/// real platform channels.
abstract class AudioRecorderService {
  /// Returns `true` if the microphone permission is currently granted.
  Future<bool> hasPermission();

  /// Starts recording to [path] (full absolute file path, including extension).
  Future<void> start(String path);

  /// Stops the active recording and returns the path it was written to.
  ///
  /// Matches the [path] passed to [start]; the caller is responsible for
  /// deleting the file if it decides to discard the recording.
  Future<String> stop();

  /// Releases any native recorder resources. Safe to call multiple times.
  Future<void> dispose();
}

// ---------------------------------------------------------------------------
// Production implementation
// ---------------------------------------------------------------------------

/// Wraps the `record` package.
///
/// Audio is encoded to AAC-LC in an MPEG-4 container (.m4a), mono, 16 kHz,
/// 64 kbps — small enough for fast uploads and Whisper resamples to 16 kHz.
class RecordPackageRecorder implements AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 16000,
          bitRate: 64000,
        ),
        path: path,
      );

  @override
  Future<String> stop() async {
    final path = await _recorder.stop();
    return path ?? '';
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
