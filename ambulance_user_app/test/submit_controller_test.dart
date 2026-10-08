import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ambulance_user_app/controllers/submit_controller.dart';
import 'package:ambulance_user_app/models/user.dart';
import 'package:ambulance_user_app/services/api_service.dart';
import 'package:ambulance_user_app/services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake Location Service
// ---------------------------------------------------------------------------

class FakeLocationService implements LocationService {
  UserLocation? locationToReturn = const UserLocation(latitude: 9.9312, longitude: 76.2673);
  LocationException? exceptionToThrow;
  bool openLocationSettingsCalled = false;
  bool openAppSettingsCalled = false;
  int getCurrentLocationCallCount = 0;

  @override
  Future<UserLocation> getCurrentLocation() async {
    getCurrentLocationCallCount++;
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    return locationToReturn!;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalled = true;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalled = true;
    return true;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

File createTempAudioFile() {
  final tempFile = File('${Directory.systemTemp.path}/test_audio_${DateTime.now().microsecondsSinceEpoch}.m4a');
  tempFile.writeAsStringSync('fake aac audio content');
  return tempFile;
}

const mockIncidentJson = {
  'id': 77,
  'user_id': 1,
  'location': {'lat': 9.9312, 'lng': 76.2673},
  'emergency_type': 'accident',
  'severity': 'high',
  'symptoms': ['fracture'],
  'victims': 1,
  'department_needed': 'Orthopedics',
  'status': 'pending',
  'assigned_hospital_id': null,
  'assigned_ambulance_id': 2,
  'created_at': '2026-10-08T15:30:00Z',
  'broadcasts': [],
  'assigned_ambulance': null,
  'transcript': 'Accident report test',
  'extracted_data': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File testAudio;
  bool fileDeleted = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    testAudio = createTempAudioFile();
    fileDeleted = false;
  });

  tearDown(() {
    if (testAudio.existsSync()) {
      testAudio.deleteSync();
    }
  });

  Future<void> fakeDelete(String path) async {
    fileDeleted = true;
  }

  group('SubmitController — location handling', () {
    test('transitions to locationServicesOff when GPS disabled', () async {
      final fakeLocation = FakeLocationService()
        ..exceptionToThrow = const LocationServiceDisabledException();

      final controller = SubmitController(
        audioPath: testAudio.path,
        locationService: fakeLocation,
        deleteFile: fakeDelete,
      );

      await controller.submit();

      expect(controller.state, SubmitState.locationServicesOff);
      expect(fileDeleted, isFalse);
    });

    test('transitions to locationDenied when permission denied', () async {
      final fakeLocation = FakeLocationService()
        ..exceptionToThrow = const LocationPermissionDeniedException();

      final controller = SubmitController(
        audioPath: testAudio.path,
        locationService: fakeLocation,
        deleteFile: fakeDelete,
      );

      await controller.submit();

      expect(controller.state, SubmitState.locationDenied);
      expect(fileDeleted, isFalse);
    });

    test('transitions to locationPermanentlyDenied when permission blocked', () async {
      final fakeLocation = FakeLocationService()
        ..exceptionToThrow = const LocationPermissionPermanentlyDeniedException();

      final controller = SubmitController(
        audioPath: testAudio.path,
        locationService: fakeLocation,
        deleteFile: fakeDelete,
      );

      await controller.submit();

      expect(controller.state, SubmitState.locationPermanentlyDenied);
      expect(fileDeleted, isFalse);
    });
  });

  group('SubmitController — upload & retry', () {
    test('successful flow transitions through uploading to success and deletes audio', () async {
      final fakeLocation = FakeLocationService();

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/incidents');
        return http.Response(jsonEncode(mockIncidentJson), 201);
      });

      final apiService = ApiService(client: mockClient);
      final controller = SubmitController(
        audioPath: testAudio.path,
        locationService: fakeLocation,
        apiService: apiService,
        currentUser: const User(id: 1, name: 'Test', phone: '9876543210'),
        deleteFile: fakeDelete,
      );

      await controller.submit();

      expect(controller.state, SubmitState.success);
      expect(controller.incident, isNotNull);
      expect(controller.incident!.id, 77);
      expect(fileDeleted, isTrue);
    });

    test('upload error transitions to error and keeps audio file', () async {
      final fakeLocation = FakeLocationService();

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'LLM rate limit reached'}),
          500,
        );
      });

      final apiService = ApiService(client: mockClient);
      final controller = SubmitController(
        audioPath: testAudio.path,
        locationService: fakeLocation,
        apiService: apiService,
        currentUser: const User(id: 1, name: 'Test', phone: '9876543210'),
        deleteFile: fakeDelete,
      );

      await controller.submit();

      expect(controller.state, SubmitState.error);
      expect(controller.errorMessage, 'LLM rate limit reached');
      expect(fileDeleted, isFalse);
    });

    test('retry skips location step if location was already acquired', () async {
      final fakeLocation = FakeLocationService();
      int callCount = 0;

      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response(jsonEncode(mockIncidentJson), 201);
      });

      final apiService = ApiService(client: mockClient);
      final controller = SubmitController(
        audioPath: testAudio.path,
        locationService: fakeLocation,
        apiService: apiService,
        currentUser: const User(id: 1, name: 'Test', phone: '9876543210'),
        deleteFile: fakeDelete,
      );

      await controller.submit();
      expect(controller.state, SubmitState.error);
      expect(fakeLocation.getCurrentLocationCallCount, 1);

      // Retry should NOT re-call location
      await controller.retry();
      expect(controller.state, SubmitState.success);
      expect(fakeLocation.getCurrentLocationCallCount, 1);
      expect(fileDeleted, isTrue);
    });

    test('re-entrancy guard blocks concurrent submit calls', () async {
      final fakeLocation = FakeLocationService();

      final mockClient = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(jsonEncode(mockIncidentJson), 201);
      });

      final apiService = ApiService(client: mockClient);
      final controller = SubmitController(
        audioPath: testAudio.path,
        locationService: fakeLocation,
        apiService: apiService,
        currentUser: const User(id: 1, name: 'Test', phone: '9876543210'),
        deleteFile: fakeDelete,
      );

      final future1 = controller.submit();
      final future2 = controller.submit(); // should be ignored

      await Future.wait([future1, future2]);

      expect(controller.state, SubmitState.success);
      expect(fakeLocation.getCurrentLocationCallCount, 1);
    });
  });

  group('ApiService.submitIncident validation', () {
    test('throws ApiException when audio file does not exist', () async {
      final apiService = ApiService(client: MockClient((_) async => http.Response('{}', 200)));

      expect(
        () => apiService.submitIncident(
          audioPath: '/non/existent/file.m4a',
          lat: 9.9312,
          lng: 76.2673,
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Audio recording is missing or empty'),
        )),
      );
    });

    test('throws ApiException when audio file is empty (0 bytes)', () async {
      final emptyFile = File('${Directory.systemTemp.path}/empty_${DateTime.now().microsecondsSinceEpoch}.m4a');
      emptyFile.writeAsStringSync('');

      final apiService = ApiService(client: MockClient((_) async => http.Response('{}', 200)));

      try {
        expect(
          () => apiService.submitIncident(
            audioPath: emptyFile.path,
            lat: 9.9312,
            lng: 76.2673,
          ),
          throwsA(isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Audio recording is missing or empty'),
          )),
        );
      } finally {
        if (emptyFile.existsSync()) emptyFile.deleteSync();
      }
    });
  });
}
