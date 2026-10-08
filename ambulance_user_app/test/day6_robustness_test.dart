import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ambulance_user_app/config/api_config.dart';
import 'package:ambulance_user_app/config/routes.dart';
import 'package:ambulance_user_app/models/user.dart';
import 'package:ambulance_user_app/screens/error_screen.dart';
import 'package:ambulance_user_app/screens/home_screen.dart';
import 'package:ambulance_user_app/screens/result_screen.dart';
import 'package:ambulance_user_app/services/api_service.dart';
import 'package:ambulance_user_app/services/cleanup_service.dart';
import 'package:ambulance_user_app/services/location_service.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({UserLocation? location, this.shouldFail = false})
      : location = location ?? const UserLocation(latitude: 9.9312, longitude: 76.2673);

  final UserLocation location;
  final bool shouldFail;

  @override
  Future<UserLocation> getCurrentLocation() async {
    if (shouldFail) {
      throw const LocationTimeoutException('GPS signal lost');
    }
    return location;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

void main() {
  const testUser = User(id: 42, name: 'Alice', phone: '9999999999');

  group('Day 6 - Demo Mode Toggle & Banner', () {
    testWidgets('Tapping Emergency Ambulance title 5 times toggles demo mode and banner',
        (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response('Not found', 404);
      });

      final api = ApiService(client: mockClient);

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          user: testUser,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      // Initially demo banner is NOT visible
      expect(find.byKey(const ValueKey('demo_mode_banner')), findsNothing);
      expect(find.byKey(const ValueKey('demo_reports_panel')), findsNothing);

      // Tap title 5 times
      final titleFinder = find.text('Emergency Ambulance');
      for (int i = 0; i < 5; i++) {
        await tester.tap(titleFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      // Now demo mode is ACTIVE
      expect(find.byKey(const ValueKey('demo_mode_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('demo_reports_panel')), findsOneWidget);
      expect(find.text('Road accident - critical'), findsOneWidget);
      expect(find.text('Chest pain - cardiac'), findsOneWidget);
      expect(find.text('Child high fever - paediatric'), findsOneWidget);
      expect(find.text('Mild fever - general'), findsOneWidget);

      // Tap 5 more times to disable
      for (int i = 0; i < 5; i++) {
        await tester.tap(titleFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('demo_mode_banner')), findsNothing);
      expect(find.byKey(const ValueKey('demo_reports_panel')), findsNothing);
    });
  });

  group('Day 6 - Demo Preset Submission & Location Fallback', () {
    testWidgets('Submitting preset with working GPS calls POST /incidents/manual and navigates to ResultScreen',
        (WidgetTester tester) async {
      Map<String, dynamic>? postedBody;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        if (request.url.path == '/incidents/manual') {
          postedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 505,
              'user_id': 42,
              'location': {'lat': postedBody!['lat'], 'lng': postedBody!['lng']},
              'emergency_type': postedBody!['emergency_type'],
              'severity': postedBody!['severity'],
              'symptoms': postedBody!['symptoms'],
              'victims': postedBody!['victims'],
              'department_needed': postedBody!['department_needed'],
              'status': 'pending',
              'broadcasts': [
                {'id': 1, 'incident_id': 505, 'target_type': 'hospital', 'target_id': 1, 'status': 'sent'}
              ],
              'created_at': DateTime.now().toIso8601String(),
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final api = ApiService(client: mockClient);
      final fakeLocation = FakeLocationService();

      await tester.pumpWidget(MaterialApp(
        initialRoute: AppRoutes.root,
        routes: {
          AppRoutes.root: (context) => HomeScreen(
                user: testUser,
                apiService: api,
                locationService: fakeLocation,
              ),
          AppRoutes.result: (context) => const ResultScreen(),
        },
      ));
      await tester.pumpAndSettle();

      // Enable demo mode
      final titleFinder = find.text('Emergency Ambulance');
      for (int i = 0; i < 5; i++) {
        await tester.tap(titleFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      // Tap preset "Road accident - critical"
      final presetButton = find.text('Road accident - critical');
      await tester.ensureVisible(presetButton);
      await tester.tap(presetButton);
      await tester.pumpAndSettle();

      // Verified POST body
      expect(postedBody, isNotNull);
      expect(postedBody!['emergency_type'], 'Road accident');
      expect(postedBody!['severity'], 'critical');
      expect(postedBody!['department_needed'], 'Trauma');
      expect(postedBody!['victims'], 2);
      expect(postedBody!['lat'], 9.9312);
      expect(postedBody!['lng'], 76.2673);

      // Verified arrived on ResultScreen with preset label as transcript
      expect(find.text('We understood your report'), findsOneWidget);
      expect(find.text('Incident #505'), findsOneWidget);
      expect(find.text('Road accident - critical'), findsOneWidget); // In transcript card
    });

    testWidgets('Submitting preset when GPS fails uses ApiConfig demo coordinates fallback',
        (WidgetTester tester) async {
      Map<String, dynamic>? postedBody;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        if (request.url.path == '/incidents/manual') {
          postedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 506,
              'user_id': 42,
              'location': {'lat': postedBody!['lat'], 'lng': postedBody!['lng']},
              'emergency_type': postedBody!['emergency_type'],
              'severity': postedBody!['severity'],
              'symptoms': postedBody!['symptoms'],
              'victims': postedBody!['victims'],
              'department_needed': postedBody!['department_needed'],
              'status': 'pending',
              'broadcasts': [],
              'created_at': DateTime.now().toIso8601String(),
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final api = ApiService(client: mockClient);
      final failingLocation = FakeLocationService(shouldFail: true);

      await tester.pumpWidget(MaterialApp(
        initialRoute: AppRoutes.root,
        routes: {
          AppRoutes.root: (context) => HomeScreen(
                user: testUser,
                apiService: api,
                locationService: failingLocation,
              ),
          AppRoutes.result: (context) => const ResultScreen(),
        },
      ));
      await tester.pumpAndSettle();

      // Enable demo mode
      final titleFinder = find.text('Emergency Ambulance');
      for (int i = 0; i < 5; i++) {
        await tester.tap(titleFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      // Tap preset "Chest pain - cardiac"
      final presetButton = find.text('Chest pain - cardiac');
      await tester.ensureVisible(presetButton);
      await tester.tap(presetButton);
      await tester.pumpAndSettle();

      // Checked fallback coordinates matched ApiConfig defaults
      expect(postedBody, isNotNull);
      expect(postedBody!['lat'], ApiConfig.demoLat);
      expect(postedBody!['lng'], ApiConfig.demoLng);
      expect(postedBody!['department_needed'], 'Cardiology');

      // Arrived at ResultScreen
      expect(find.text('We understood your report'), findsOneWidget);
      expect(find.text('Incident #506'), findsOneWidget);
    });
  });

  group('Day 6 - Server Status Indicator', () {
    testWidgets('Shows connected on success and updates on tap to refresh',
        (WidgetTester tester) async {
      int healthCalls = 0;
      bool serverHealthy = true;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/health') {
          healthCalls++;
          if (serverHealthy) {
            return http.Response(jsonEncode({'status': 'ok'}), 200);
          } else {
            return http.Response('Server Error', 500);
          }
        }
        return http.Response('Not found', 404);
      });

      final api = ApiService(client: mockClient);

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(user: testUser, apiService: api),
      ));
      await tester.pumpAndSettle();

      expect(healthCalls, 1);
      expect(find.text('Server connected'), findsOneWidget);

      // Now server fails
      serverHealthy = false;
      await tester.tap(find.byKey(const ValueKey('server_status_indicator')));
      await tester.pumpAndSettle();

      expect(healthCalls, 2);
      expect(find.text('Server unreachable'), findsOneWidget);
    });
  });

  group('Day 6 - Stale File Cleanup', () {
    test('Deletes files older than 24h and preserves fresh and active files', () async {
      final tempDir = await Directory.systemTemp.createTemp('stale_cleanup_test_');

      try {
        final now = DateTime.now();

        // 1. Old file (30 hours old) -> should be deleted
        final oldFile = File('${tempDir.path}/report_old.m4a');
        await oldFile.writeAsString('old audio');
        await oldFile.setLastModified(now.subtract(const Duration(hours: 30)));

        // 2. Fresh file (2 hours old) -> should NOT be deleted
        final freshFile = File('${tempDir.path}/report_fresh.m4a');
        await freshFile.writeAsString('fresh audio');
        await freshFile.setLastModified(now.subtract(const Duration(hours: 2)));

        // 3. Active file (even if 30 hours old) -> should NOT be deleted
        final activeFile = File('${tempDir.path}/report_active.m4a');
        await activeFile.writeAsString('active audio');
        await activeFile.setLastModified(now.subtract(const Duration(hours: 30)));

        // 4. Other extension file (old) -> should NOT be deleted
        final otherFile = File('${tempDir.path}/other_old.txt');
        await otherFile.writeAsString('text');
        await otherFile.setLastModified(now.subtract(const Duration(hours: 30)));

        const cleanupService = CleanupService();
        final deleted = await cleanupService.cleanupStaleAudioFiles(
          maxAge: const Duration(hours: 24),
          activeFilePath: activeFile.path,
          getTempDir: () async => tempDir,
        );

        expect(deleted, 1);
        expect(await oldFile.exists(), isFalse);
        expect(await freshFile.exists(), isTrue);
        expect(await activeFile.exists(), isTrue);
        expect(await otherFile.exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Day 6 - Global Error Safety', () {
    testWidgets('GlobalErrorScreen renders friendly UI and navigates to home',
        (WidgetTester tester) async {
      bool backHomeTapped = false;

      await tester.pumpWidget(MaterialApp(
        home: GlobalErrorScreen(
          onBackHome: () => backHomeTapped = true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);

      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();

      expect(backHomeTapped, isTrue);
    });
  });
}
