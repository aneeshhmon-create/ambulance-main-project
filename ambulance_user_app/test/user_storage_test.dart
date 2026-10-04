import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ambulance_user_app/models/user.dart';
import 'package:ambulance_user_app/services/user_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = UserStorage();
  });

  group('UserStorage', () {
    test('loadUser returns null when storage is empty', () async {
      final user = await storage.loadUser();
      expect(user, isNull);
    });

    test('saveUser persists user and loadUser retrieves it', () async {
      const user = User(
        id: 42,
        name: 'Rahul Sharma',
        phone: '9876543210',
      );

      await storage.saveUser(user);
      final loaded = await storage.loadUser();

      expect(loaded, isNotNull);
      expect(loaded?.id, 42);
      expect(loaded?.name, 'Rahul Sharma');
      expect(loaded?.phone, '9876543210');
      expect(loaded, equals(user));
    });

    test('clearUser removes saved user profile', () async {
      const user = User(
        id: 10,
        name: 'Anjali Menon',
        phone: '9876500000',
      );

      await storage.saveUser(user);
      expect(await storage.loadUser(), isNotNull);

      await storage.clearUser();
      final afterClear = await storage.loadUser();
      expect(afterClear, isNull);
    });

    test('loadUser handles corrupted JSON by returning null', () async {
      SharedPreferences.setMockInitialValues({
        'saved_user_profile': 'not-a-valid-json-string',
      });

      final user = await storage.loadUser();
      expect(user, isNull);
    });
  });
}
