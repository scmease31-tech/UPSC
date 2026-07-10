import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages app-wide dark/light theme state with persistence.
///
/// Usage:
/// ```dart
/// final theme = context.watch<ThemeProvider>();
/// theme.toggleTheme();   // flip between dark/light
/// theme.isDark;          // check current mode
/// ```
class ThemeProvider extends ChangeNotifier {
  static const _key = 'isDarkMode';

  ThemeMode _themeMode = ThemeMode.light;

  ThemeProvider() {
    _loadTheme();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  /// Toggle between dark and light mode.
  Future<void> toggleTheme() async {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    await _persist();
  }

  /// Set a specific theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkStored = prefs.getBool(_key) ?? false;
    _themeMode = isDarkStored ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, isDark);
  }
}
