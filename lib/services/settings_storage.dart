import 'package:shared_preferences/shared_preferences.dart';

class SettingsStorage {
  static const _vibrationKey = 'setting_vibration';
  static const _timerKey = 'setting_timer';
  static const _darkModeKey = 'setting_dark_mode';

  Future<bool> loadVibration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vibrationKey) ?? true;
  }

  Future<bool> loadTimer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_timerKey) ?? true;
  }

  Future<bool> loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  Future<void> saveVibration(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationKey, value);
  }

  Future<void> saveTimer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_timerKey, value);
  }

  Future<void> saveDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }
}
