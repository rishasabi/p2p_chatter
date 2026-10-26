// providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/custom_theme_store.dart';
import '../services/settings_store.dart';
import '../theme/app_theme.dart';
import '../theme/custom_theme.dart';

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

/// A custom palette, used in place of the light and dark themes while on.
class CustomThemeNotifier extends StateNotifier<CustomThemeSettings> {
  CustomThemeNotifier() : super(CustomThemeStore().settings);

  /// Switches the whole app to [config] and saves it.
  void apply(CustomThemeConfig config) => _save((config: config, enabled: true));

  /// Back to the light or dark theme; the palette is kept for next time.
  void turnOff() {
    if (state.enabled) _save((config: state.config, enabled: false));
  }

  void _save(CustomThemeSettings settings) {
    state = settings;
    CustomThemeStore().save(settings);
  }
}

final customThemeProvider = StateNotifierProvider<CustomThemeNotifier, CustomThemeSettings>((ref) {
  return CustomThemeNotifier();
});

/// The theme a custom palette makes, or null while none is on. Built once
/// per palette rather than on every rebuild of the app.
final customThemeDataProvider = Provider<ThemeData?>((ref) {
  final custom = ref.watch(customThemeProvider);
  return custom.enabled && custom.config != null ? AppTheme.custom(custom.config!) : null;
});
