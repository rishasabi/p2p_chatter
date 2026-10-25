// providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_store.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  // Saved choice, defaulting to Ember's dark aesthetic
  ThemeNotifier()
      : super(SettingsStore().getString(SettingsStore.themeMode) == 'light'
            ? ThemeMode.light
            : ThemeMode.dark);

  void toggleTheme(bool isDark) {
    setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    SettingsStore().set(SettingsStore.themeMode, mode == ThemeMode.light ? 'light' : 'dark');
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
