import 'ble_service.dart';
import 'settings_store.dart';

/// What plays when a message arrives while its chat isn't on screen. The
/// sounds are in assets/sounds/ (made by tool/make_sounds.dart); with any of
/// them the notification itself stays quiet and only vibrates, so the two
/// never play at once. On silent or vibrate, the phone only vibrates.
enum AlertSound {
  chime('Default chime', 'For everyday messages', 'assets/sounds/chime_default.wav'),
  siren('Urgent siren', 'Loud and rising, to cut through a noisy crowd', 'assets/sounds/urgent_alert.wav'),
  pulse('Tactical pulse', 'Two low, soft knocks for quiet tents and night shifts', 'assets/sounds/tactical_pulse.wav'),
  system('System default', 'Your phone\'s own notification sound', null),
  vibrate('Vibrate only', 'No sound', null);

  final String label;
  final String description;
  final String? asset;
  const AlertSound(this.label, this.description, this.asset);

  /// The saved choice, the chime unless another was picked.
  static AlertSound get current {
    final saved = SettingsStore().getString(SettingsStore.alertSound);
    return AlertSound.values.where((s) => s.name == saved).firstOrNull ?? chime;
  }

  static Future<void> choose(AlertSound sound) => SettingsStore().set(SettingsStore.alertSound, sound.name);

  /// Whether the system notification should stay quiet, leaving it to [play].
  bool get notificationSilent => this != system;

  /// Plays this sound now: for a new message, or as a preview in Settings.
  Future<void> play({bool preview = false}) async {
    final ble = BleService();
    if (asset != null) {
      await ble.playSound(asset!);
    } else if (this == system && preview) {
      // Otherwise the notification plays it
      await ble.playSystemSound();
    }
  }
}
