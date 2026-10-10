import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ambulance_user_app/models/user.dart';
import 'package:ambulance_user_app/services/api_service.dart';

/// Unit tests for [ApiService].
void main() {
  group('ApiService.checkHealth()', () {
    test('returns parsed JSON on HTTP 200', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'status': 'ok', 'version': '1.0'}),
            200,
          ));
      final api = ApiService(client: client);

      final result = await api.checkHealth();

      expect(result, isA<Map>());
      expect(result['status'], equals('ok'));
    });

    test('throws ApiException with status code on HTTP 500', () async {
      final client =
          MockClient((_) async => http.Response('Internal Server Error', 500));
      final api = ApiService(client: client);

      expect(
        () => api.checkHealth(),
        throwsA(
          predicate<ApiException>(
            (e) => e.message.contains('500'),
            'message contains status code 500',
          ),
        ),
      );
    });

    test('throws ApiException on non-JSON response body', () async {
      final client = MockClient(
          (_) async => http.Response('<!DOCTYPE html><html></html>', 200));
      final api = ApiService(client: client);

      expect(
        () => api.checkHealth(),
        throwsA(
          predicate<ApiException>(
            (e) => e.message.toLowerCase().contains('unexpected response'),
            'message mentions unexpected response',
          ),
        ),
      );
    });

    test('throws ApiException with network message on SocketException',
        () async {
      final client = MockClient((_) async {
        throw http.ClientException('Connection refused');
      });
      final api = ApiService(client: client);

      expect(
        () => api.checkHealth(),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException with timeout message after 5 seconds', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return http.Response('', 200);
      });
      final api = ApiService(client: client);

      expect(
        () => api.checkHealth(),
        throwsA(
          predicate<ApiException>(
            (e) => e.message.toLowerCase().contains('timed out'),
            'message mentions timed out',
          ),
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('ApiService.registerUser()', () {
    test('returns User on HTTP 201 (new user created)', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/users');
        final body = jsonDecode(request.body);
        expect(body['name'], 'Alice Nair');
        expect(body['phone'], '9876543210');

        return http.Response(
          jsonEncode({
            'id': 101,
            'name': 'Alice Nair',
            'phone': '9876543210',
            'created_at': '2026-10-04T12:00:00Z',
          }),
          201,
        );
      });

      final api = ApiService(client: client);
      final user = await api.registerUser('Alice Nair', '9876543210');

      expect(user, isA<User>());
      expect(user.id, 101);
      expect(user.name, 'Alice Nair');
      expect(user.phone, '9876543210');
    });

    test('returns User on HTTP 200 (existing user returned)', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 101,
            'name': 'Alice M. Nair',
            'phone': '9876543210',
            'created_at': '2026-10-04T12:00:00Z',
          }),
          200,
        );
      });

      final api = ApiService(client: client);
      final user = await api.registerUser('Alice M. Nair', '9876543210');

      expect(user.id, 101);
      expect(user.name, 'Alice M. Nair');
      expect(user.phone, '9876543210');
    });

    test('surfaces backend 422 error message in ApiException', () async {
      const errorMessage =
          "Invalid phone number '123'. Phone number must contain exactly 10 digits after removing spaces, dashes, or a leading '+91' / '0'.";

      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': errorMessage}),
          422,
        );
      });

      final api = ApiService(client: client);

      expect(
        () => api.registerUser('Invalid User', '123'),
        throwsA(
          predicate<ApiException>(
            (e) => e.message == errorMessage,
            'message matches backend 422 detail string exactly',
          ),
        ),
      );
    });

    test('throws ApiException on HTTP 500', () async {
      final client = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final api = ApiService(client: client);

      expect(
        () => api.registerUser('Test User', '9876543210'),
        throwsA(
          predicate<ApiException>(
            (e) => e.message.contains('500'),
            'message contains status 500',
          ),
        ),
      );
    });
  });
}
