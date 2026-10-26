import 'dart:convert';

import 'package:flutter/material.dart';

/// The colours a custom theme sets, in the order the editor lists them. [key]
/// is the name in a shared theme file and must never change.
enum ThemeColorRole {
  primary('primary', 'Buttons and links'),
  surface('surface', 'Background'),
  cardBackground('cardBackground', 'Cards and panels'),
  appBar('appBar', 'Top bar'),
  myBubble('myBubble', 'Your messages'),
  myBubbleText('myBubbleText', 'Your message text'),
  peerBubble('peerBubble', 'Their messages'),
  peerBubbleText('peerBubbleText', 'Their message text'),
  reachIndicator('reachIndicator', 'Reachable peers'),
  accentEmber('accentEmber', 'Accent: you, Send, selection');

  final String key;
  final String label;
  const ThemeColorRole(this.key, this.label);
}

/// A palette for the whole app, one colour per [ThemeColorRole], that a team
/// can pass around as a small JSON file (`.chattertheme`) so everyone reads
/// the same high-contrast or night-vision colours:
///
/// ```json
/// {"name": "Tactical Red Night", "version": 1, "colors": {"primary": "#E11D48", ...}}
/// ```
@immutable
class CustomThemeConfig {
  /// The file format this app writes; files from a newer one are refused.
  static const formatVersion = 1;
  static const fileExtension = 'chattertheme';
  static const maxNameLength = 40;

  final String name;
  final Map<ThemeColorRole, Color> _colors;

  CustomThemeConfig({required String name, required Map<ThemeColorRole, Color> colors})
      : name = _cleanName(name),
        _colors = Map.unmodifiable({
          // Every role is always set: a file missing some takes them from the default
          for (final role in ThemeColorRole.values) role: _opaque(colors[role] ?? lanternNight._colors[role]!),
        });

  const CustomThemeConfig._preset(this.name, this._colors);

  Color operator [](ThemeColorRole role) => _colors[role]!;

  /// Whether the background is dark, so text and controls go light on it.
  bool get isDark => ThemeData.estimateBrightnessForColor(this[ThemeColorRole.surface]) == Brightness.dark;

  /// Text colours too close to their background to read easily: under
  /// WCAG AA's 4.5:1. (The accent isn't checked: it's always a filled shape
  /// whose icon is picked to read on it.)
  List<({String what, double ratio, double needed})> lowContrast() {
    final surface = this[ThemeColorRole.surface];
    return [
      ('Your message text', this[ThemeColorRole.myBubbleText], this[ThemeColorRole.myBubble], 4.5),
      ('Their message text', this[ThemeColorRole.peerBubbleText], this[ThemeColorRole.peerBubble], 4.5),
      ('Buttons and links on the background', this[ThemeColorRole.primary], surface, 4.5),
      ('Reachable peers on the background', this[ThemeColorRole.reachIndicator], surface, 4.5),
    ]
        .map((p) => (what: p.$1, ratio: contrastRatio(p.$2, p.$3), needed: p.$4))
        .where((p) => p.ratio < p.needed)
        .toList();
  }

  CustomThemeConfig withName(String name) => CustomThemeConfig(name: name, colors: _colors);

  CustomThemeConfig withColor(ThemeColorRole role, Color color) =>
      CustomThemeConfig(name: name, colors: {..._colors, role: color});

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': formatVersion,
        'colors': {for (final role in ThemeColorRole.values) role.key: colorToHex(this[role])},
      };

  /// Pretty-printed, for the clipboard and theme files.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Reads a theme someone shared. Throws a [FormatException] whose message
  /// says what's wrong, for showing as is.
  static CustomThemeConfig decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text.trim());
    } on FormatException {
      throw const FormatException('This isn\'t a Chatter theme: it isn\'t valid JSON.');
    }
    return fromJson(json);
  }

  static CustomThemeConfig fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('This isn\'t a Chatter theme: expected a JSON object.');
    }
    final version = json['version'];
    if (version is! int || version < 1) {
      throw const FormatException('This isn\'t a Chatter theme: it has no version.');
    }
    if (version > formatVersion) {
      throw const FormatException('This theme was made by a newer Chatter. Update the app to use it.');
    }
    final colors = json['colors'];
    if (colors is! Map<String, dynamic>) {
      throw const FormatException('This isn\'t a Chatter theme: it has no colors.');
    }
    final parsed = <ThemeColorRole, Color>{};
    for (final role in ThemeColorRole.values) {
      final value = colors[role.key];
      if (value == null) continue;
      final color = value is String ? parseHexColor(value) : null;
      if (color == null) throw FormatException('"${role.key}" should be a colour like #E11D48, not $value.');
      parsed[role] = color;
    }
    if (parsed.isEmpty) {
      throw const FormatException('This isn\'t a Chatter theme: none of its colors are ones Chatter uses.');
    }
    final name = json['name'];
    return CustomThemeConfig(name: name is String ? name : '', colors: parsed);
  }

  static String _cleanName(String name) {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return 'Custom theme';
    return n.length > maxNameLength ? n.substring(0, maxNameLength) : n;
  }

  // Bubbles and backgrounds see-through to nothing would be unreadable
  static Color _opaque(Color c) => c.withAlpha(0xFF);

  @override
  bool operator ==(Object other) =>
      other is CustomThemeConfig &&
      other.name == name &&
      ThemeColorRole.values.every((role) => other[role] == this[role]);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(ThemeColorRole.values.map((r) => this[r])));

  /// Chatter's own dark look, as a starting point.
  static const lanternNight = CustomThemeConfig._preset('Lantern night', {
    ThemeColorRole.primary: Color(0xFFFFB547),
    ThemeColorRole.surface: Color(0xFF0E1020),
    ThemeColorRole.cardBackground: Color(0xFF13152A),
    ThemeColorRole.appBar: Color(0xFF0E1020),
    ThemeColorRole.myBubble: Color(0xFFFFB547),
    ThemeColorRole.myBubbleText: Color(0xFF241400),
    ThemeColorRole.peerBubble: Color(0xFF20243B),
    ThemeColorRole.peerBubbleText: Color(0xFFECEBF7),
    ThemeColorRole.reachIndicator: Color(0xFF74D1B0),
    ThemeColorRole.accentEmber: Color(0xFFFFB547),
  });

  /// Chatter's own light look.
  static const lanternDawn = CustomThemeConfig._preset('Lantern dawn', {
    ThemeColorRole.primary: Color(0xFF8A4B00),
    ThemeColorRole.surface: Color(0xFFF4F2FA),
    ThemeColorRole.cardBackground: Color(0xFFFAF9FD),
    ThemeColorRole.appBar: Color(0xFFF4F2FA),
    ThemeColorRole.myBubble: Color(0xFFFFB547),
    ThemeColorRole.myBubbleText: Color(0xFF241400),
    ThemeColorRole.peerBubble: Color(0xFFFFFFFF),
    ThemeColorRole.peerBubbleText: Color(0xFF1B1A2E),
    ThemeColorRole.reachIndicator: Color(0xFF136B46),
    ThemeColorRole.accentEmber: Color(0xFFFFB547),
  });

  /// Reds on navy, easy on night vision.
  static const tacticalRedNight = CustomThemeConfig._preset('Tactical Red Night', {
    ThemeColorRole.primary: Color(0xFFE11D48),
    ThemeColorRole.surface: Color(0xFF0F172A),
    ThemeColorRole.cardBackground: Color(0xFF1E293B),
    ThemeColorRole.appBar: Color(0xFF090D16),
    ThemeColorRole.myBubble: Color(0xFFBE123C),
    ThemeColorRole.myBubbleText: Color(0xFFFFFFFF),
    ThemeColorRole.peerBubble: Color(0xFF334155),
    ThemeColorRole.peerBubbleText: Color(0xFFF8FAFC),
    ThemeColorRole.reachIndicator: Color(0xFF22C55E),
    ThemeColorRole.accentEmber: Color(0xFFF43F5E),
  });

  /// True black, which OLED screens don't light at all: saves battery.
  static const oledBlack = CustomThemeConfig._preset('OLED black', {
    ThemeColorRole.primary: Color(0xFFFFD60A),
    ThemeColorRole.surface: Color(0xFF000000),
    ThemeColorRole.cardBackground: Color(0xFF0D0D0D),
    ThemeColorRole.appBar: Color(0xFF000000),
    ThemeColorRole.myBubble: Color(0xFFFFD60A),
    ThemeColorRole.myBubbleText: Color(0xFF000000),
    ThemeColorRole.peerBubble: Color(0xFF1C1C1E),
    ThemeColorRole.peerBubbleText: Color(0xFFFFFFFF),
    ThemeColorRole.reachIndicator: Color(0xFF30D158),
    ThemeColorRole.accentEmber: Color(0xFFFFD60A),
  });

  /// Black on white with strong blues, for reading in direct sunlight.
  static const sunlight = CustomThemeConfig._preset('Sunlight', {
    ThemeColorRole.primary: Color(0xFF0039A6),
    ThemeColorRole.surface: Color(0xFFFFFFFF),
    ThemeColorRole.cardBackground: Color(0xFFF2F2F2),
    ThemeColorRole.appBar: Color(0xFFFFFFFF),
    ThemeColorRole.myBubble: Color(0xFF0039A6),
    ThemeColorRole.myBubbleText: Color(0xFFFFFFFF),
    ThemeColorRole.peerBubble: Color(0xFFE6E6E6),
    ThemeColorRole.peerBubbleText: Color(0xFF000000),
    ThemeColorRole.reachIndicator: Color(0xFF006B2D),
    ThemeColorRole.accentEmber: Color(0xFF0039A6),
  });

  static const presets = [lanternNight, lanternDawn, tacticalRedNight, oledBlack, sunlight];
}

/// `#RRGGBB`, upper case.
String colorToHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// A colour from `#RRGGBB` (the `#` optional), or null if it isn't one.
Color? parseHexColor(String text) {
  final hex = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

/// WCAG contrast ratio between two opaque colours, 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [preferred] if it reads on [background], else black or white, whichever
/// reads better.
Color readableOn(Color background, [Color? preferred]) {
  if (preferred != null && contrastRatio(preferred, background) >= 4.5) return preferred;
  return contrastRatio(Colors.white, background) >= contrastRatio(Colors.black, background)
      ? Colors.white
      : Colors.black;
}
