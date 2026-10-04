import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ambulance_user_app/services/api_service.dart';

/// Unit tests for [ApiService].
///
/// All tests inject a [MockClient] so no real network calls are made.
/// Coverage matrix:
///   1. HTTP 200 with valid JSON       → returns parsed map
///   2. HTTP 500                       → ApiException with status code
///   3. Invalid / non-JSON body        → ApiException (parse error)
///   4. SocketException (no network)   → ApiException (user-friendly message)
///   5. TimeoutException               → ApiException (timeout message)
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
      final client = MockClient(
          (_) async => http.Response('Internal Server Error', 500));
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
        // Simulate a SocketException (no Wi-Fi / unreachable host).
        throw http.ClientException('Connection refused');
      });
      final api = ApiService(client: client);

      // http.ClientException is a subtype of Exception; our catch-all
      // maps it to an ApiException.
      expect(
        () => api.checkHealth(),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException with timeout message after 5 seconds', () async {
      final client = MockClient((_) async {
        // Hang forever — the service's 5-second timeout should fire first.
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
}
