import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Service responsible for managing local persistence of [User] identity.
class UserStorage {
  static const String _userKey = 'saved_user_profile';

  /// Saves the [User] to local persistent storage.
  Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(user.toJson());
    await prefs.setString(_userKey, jsonString);
  }

  /// Loads the saved [User] from local persistent storage.
  /// Returns `null` if no user has been saved yet or if data is corrupted.
  Future<User?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_userKey);
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }
    try {
      final Map<String, dynamic> map =
          jsonDecode(jsonString) as Map<String, dynamic>;
      return User.fromJson(map);
    } catch (_) {
      // If corrupted, clean up and return null
      await clearUser();
      return null;
    }
  }

  /// Clears the currently saved [User] from storage.
  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }
}
