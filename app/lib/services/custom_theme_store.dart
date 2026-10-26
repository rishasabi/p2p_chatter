import 'package:flutter/foundation.dart';

import '../theme/custom_theme.dart';
import 'local_store.dart';

/// The user's custom theme, persisted in custom_theme.json, and whether it's
/// switched on. Kept when switched off, so the editor opens on it again.
typedef CustomThemeSettings = ({CustomThemeConfig? config, bool enabled});

/// [load] once at startup, so the first frame is already in the right colours.
class CustomThemeStore {
  static final CustomThemeStore _instance = CustomThemeStore._();
  factory CustomThemeStore() => _instance;
  CustomThemeStore._();

  static const _file = 'custom_theme.json';

  CustomThemeSettings _settings = (config: null, enabled: false);
  CustomThemeSettings get settings => _settings;

  Future<void> load() async {
    final stored = await LocalStore.read(_file);
    if (stored['theme'] == null) return;
    try {
      _settings = (config: CustomThemeConfig.fromJson(stored['theme']), enabled: stored['enabled'] == true);
    } on FormatException catch (e) {
      debugPrint('CustomThemeStore: ignoring saved theme: ${e.message}');
    }
  }

  Future<void> save(CustomThemeSettings settings) async {
    _settings = settings;
    await LocalStore.write(_file, {
      'enabled': settings.enabled,
      if (settings.config != null) 'theme': settings.config!.toJson(),
    });
  }
}
