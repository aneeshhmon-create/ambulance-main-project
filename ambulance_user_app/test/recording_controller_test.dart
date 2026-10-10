import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:ambulance_user_app/controllers/recording_controller.dart';
import 'package:ambulance_user_app/services/audio_recorder_service.dart';

// ---------------------------------------------------------------------------
// Fake recorder
// ---------------------------------------------------------------------------

class FakeAudioRecorderService implements AudioRecorderService {
  bool permissionResult = true;
  bool throwOnStart = false;
  bool throwOnStop = false;

  bool startCalled = false;
  bool stopCalled = false;
  bool disposeCalled = false;
  String? startedPath;

  @override
  Future<bool> hasPermission() async => permissionResult;

  @override
  Future<void> start(String path) async {
    if (throwOnStart) throw Exception('start failed');
    startCalled = true;
    startedPath = path;
  }

  @override
  Future<String> stop() async {
    if (throwOnStop) throw Exception('stop failed');
    stopCalled = true;
    return startedPath ?? '';
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<Directory> Function() fakeTempDir() {
  return () => Future.value(Directory.systemTemp);
}

RecordingController makeController(
  FakeAudioRecorderService fake, {
  PermissionStatus permissionStatus = PermissionStatus.granted,
  Future<void> Function(String)? deleteFile,
}) =>
    RecordingController(
      recorderService: fake,
      getTempDir: fakeTempDir(),
      checkAndRequestPermission: () => Future.value(permissionStatus),
      deleteFile: deleteFile ?? (_) async {},
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecordingController — permission handling', () {
    test('startRecording transitions to recording when permission granted', () async {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake, permissionStatus: PermissionStatus.granted);

      await ctrl.startRecording();

      expect(ctrl.state, RecordingState.recording);
      expect(fake.startCalled, isTrue);

      await ctrl.dispose();
    });

    test('startRecording sets permissionDenied when mic denied', () async {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake, permissionStatus: PermissionStatus.denied);

      await ctrl.startRecording();

      expect(ctrl.state, RecordingState.permissionDenied);
      expect(fake.startCalled, isFalse);

      await ctrl.dispose();
    });

    test('startRecording sets permissionPermanentlyDenied when permanently denied', () async {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(
        fake,
        permissionStatus: PermissionStatus.permanentlyDenied,
      );

      await ctrl.startRecording();

      expect(ctrl.state, RecordingState.permissionPermanentlyDenied);
      expect(fake.startCalled, isFalse);

      await ctrl.dispose();
    });
  });

  group('RecordingController — duration rules', () {
    test('stopping after >= 2 s yields recorded state', () {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.recording);

        // Advance 3 seconds
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        ctrl.stopRecording();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.recorded);
        expect(ctrl.recordedPath, isNotNull);
      });

      ctrl.dispose();
    });

    test('stopping before 2 s yields tooShort and clears path', () {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.recording);

        // Only 1 second elapsed
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        ctrl.stopRecording();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.tooShort);
        expect(ctrl.recordedPath, isNull);
      });

      ctrl.dispose();
    });

    test('auto-stops at 60 s and yields recorded state', () {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.recording);

        // Jump past maxDuration (60s)
        async.elapse(const Duration(seconds: 61));
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.recorded);
        expect(ctrl.elapsed, greaterThanOrEqualTo(RecordingController.maxDuration));
      });

      ctrl.dispose();
    });
  });

  group('RecordingController — reRecord', () {
    test('reRecord from recorded state returns to idle, clears path', () {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        ctrl.stopRecording();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.recorded);

        ctrl.reRecord();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.idle);
        expect(ctrl.recordedPath, isNull);
      });

      ctrl.dispose();
    });
  });

  group('RecordingController — recorder error', () {
    test('error during start sets error state', () {
      final fake = FakeAudioRecorderService()..throwOnStart = true;
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.error);
        expect(ctrl.errorMessage, isNotEmpty);
      });

      ctrl.dispose();
    });

    test('error during stop sets error state', () {
      final fake = FakeAudioRecorderService()..throwOnStop = true;
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        ctrl.stopRecording();
        async.flushMicrotasks();

        expect(ctrl.state, RecordingState.error);
      });

      ctrl.dispose();
    });
  });

  group('RecordingController — elapsed timer', () {
    test('elapsed increments each second while recording', () {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));
        expect(ctrl.elapsed, 5);
      });

      ctrl.dispose();
    });

    test('elapsed resets to 0 on reRecord', () {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        ctrl.stopRecording();
        async.flushMicrotasks();
        ctrl.reRecord();
        async.flushMicrotasks();

        expect(ctrl.elapsed, 0);
      });

      ctrl.dispose();
    });
  });

  group('RecordingController — lifecycle / dispose', () {
    test('dispose during recording does not throw and calls recorder.stop', () async {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake);

      await ctrl.startRecording();
      expect(ctrl.state, RecordingState.recording);

      await ctrl.dispose();
      expect(fake.stopCalled, isTrue);
      expect(fake.disposeCalled, isTrue);
    });

    test('dispose in recorded state does NOT delete the accepted file', () async {
      final fake = FakeAudioRecorderService();
      final ctrl = makeController(fake);

      fakeAsync((async) {
        ctrl.startRecording();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        ctrl.stopRecording();
        async.flushMicrotasks();
      });

      expect(ctrl.recordedPath, isNotNull);

      await ctrl.dispose();

      expect(fake.disposeCalled, isTrue);
      expect(fake.stopCalled, isTrue);
    });
  });
}
