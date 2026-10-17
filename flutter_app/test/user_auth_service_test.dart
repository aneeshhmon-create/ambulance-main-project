import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ambulance_app/user_app/services/api_service.dart';
import 'package:ambulance_app/user_app/services/auth_service.dart';
import 'package:ambulance_app/user_app/services/user_storage.dart';

/// Unit tests for [UserAuthService] (everything except the Google picker).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserStorage userStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    userStorage = UserStorage();
  });

  UserAuthService serviceFor(http.Client client) => UserAuthService(
        client: client,
        userStorage: userStorage,
      );

  const registration = PendingUserRegistration(
    registrationToken: 'reg-token',
    name: 'Asha Nair',
    email: 'asha@gmail.com',
  );

  Map<String, dynamic> signedInBody() => {
        'registration_required': false,
        'role': 'user',
        'access_token': 'jwt-123',
        'token_type': 'bearer',
        'account': {
          'id': 7,
          'name': 'Asha Nair',
          'email': 'asha@gmail.com',
          'photo_url': null,
          'phone': '9876543210',
          'hospital_id': null,
        },
      };

  group('devSignIn', () {
    test('existing account is signed in and persisted', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/auth/dev-login');
        expect(jsonDecode(request.body)['role'], 'user');
        return http.Response(jsonEncode(signedInBody()), 200);
      });
      final auth = serviceFor(client);

      final outcome = await auth.devSignIn('asha@gmail.com');

      expect(outcome.user!.id, 7);
      expect(outcome.registration, isNull);
      expect(await auth.getToken(), 'jwt-123');
      expect((await userStorage.loadUser())!.phone, '9876543210');
    });

    test('new account asks for registration and saves nothing', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'registration_required': true,
              'role': 'user',
              'registration_token': 'reg-token',
              'google_profile': {
                'email': 'asha@gmail.com',
                'name': 'Asha Nair',
                'photo_url': null,
              },
            }),
            200,
          ));
      final auth = serviceFor(client);

      final outcome = await auth.devSignIn('asha@gmail.com');

      expect(outcome.user, isNull);
      expect(outcome.registration!.registrationToken, 'reg-token');
      expect(outcome.registration!.name, 'Asha Nair');
      expect(await auth.getToken(), isNull);
      expect(await userStorage.loadUser(), isNull);
    });

    test('404 reports that dev login is disabled', () async {
      final auth = serviceFor(
          MockClient((_) async => http.Response('{"detail":"nope"}', 404)));

      expect(
        () => auth.devSignIn('a@b.com'),
        throwsA(predicate<ApiException>((e) => e.message.contains('disabled'))),
      );
    });
  });

  group('registerUser', () {
    test('sends the details, then stores the session', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/auth/register/user');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['registration_token'], 'reg-token');
        expect(body['name'], 'Asha Nair');
        expect(body['phone'], '9876543210');
        return http.Response(jsonEncode(signedInBody()), 201);
      });
      final auth = serviceFor(client);

      final user = await auth.registerUser(
        registration: registration,
        name: 'Asha Nair',
        phone: '9876543210',
      );

      expect(user.name, 'Asha Nair');
      expect(await auth.getToken(), 'jwt-123');
      expect((await userStorage.loadUser())!.id, 7);
    });

    test('surfaces the server message on conflict', () async {
      final auth = serviceFor(MockClient((_) async => http.Response(
            jsonEncode({'detail': 'This phone number is already registered.'}),
            409,
          )));

      expect(
        () => auth.registerUser(
          registration: registration,
          name: 'Asha',
          phone: '9876543210',
        ),
        throwsA(predicate<ApiException>(
            (e) => e.message.contains('already registered'))),
      );
    });
  });

  test('signOut clears the token and the saved user', () async {
    final auth = serviceFor(
        MockClient((_) async => http.Response(jsonEncode(signedInBody()), 200)));
    await auth.devSignIn('asha@gmail.com');

    await auth.signOut();

    expect(await auth.getToken(), isNull);
    expect(await userStorage.loadUser(), isNull);
  });
}
