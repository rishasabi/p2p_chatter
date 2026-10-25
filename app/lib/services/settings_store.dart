import 'local_store.dart';

/// User settings, persisted in settings.json. [load] once at startup; reads
/// are synchronous after that.
class SettingsStore {
  static final SettingsStore _instance = SettingsStore._();
  factory SettingsStore() => _instance;
  SettingsStore._();

  static const themeMode = 'themeMode';
  static const readReceipts = 'readReceipts';
  static const backgroundSync = 'backgroundSync';
  static const publishToDht = 'publishToDht';

  Map<String, dynamic> _values = {};

  Future<void> load() async {
    _values = await LocalStore.read('settings.json');
  }

  bool getBool(String key, {required bool fallback}) {
    final value = _values[key];
    return value is bool ? value : fallback;
  }

  String? getString(String key) {
    final value = _values[key];
    return value is String ? value : null;
  }

  Future<void> set(String key, Object value) async {
    _values[key] = value;
    await LocalStore.write('settings.json', _values);
  }
}
