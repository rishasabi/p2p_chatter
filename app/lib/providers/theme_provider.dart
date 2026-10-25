// providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_store.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  // Saved choice, defaulting to Ember's dark aesthetic
  ThemeNotifier() : super(_parse(SettingsStore().getString(SettingsStore.themeMode)));

  static ThemeMode _parse(String? saved) => switch (saved) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  void toggleTheme(bool isDark) {
    setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    SettingsStore().set(SettingsStore.themeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    });
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
