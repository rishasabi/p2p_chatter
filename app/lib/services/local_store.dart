import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Small JSON documents in the app's private storage (profile, contacts).
class LocalStore {
  /// Skips storage entirely; real file I/O never completes inside widget tests.
  static bool isTestMode = false;

  static Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, name));
  }

  /// Returns the stored object, or an empty map if there is none or storage
  /// isn't available (e.g. in tests).
  static Future<Map<String, dynamic>> read(String name) async {
    if (isTestMode) return {};
    try {
      final file = await _file(name);
      if (!await file.exists()) return {};
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, dynamic> ? data : {};
    } catch (e) {
      debugPrint('LocalStore: could not read $name: $e');
      return {};
    }
  }

  static Future<void> write(String name, Map<String, dynamic> data) async {
    if (isTestMode) return;
    try {
      final file = await _file(name);
      // Write then rename, so a crash mid-write can't leave a truncated file
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('LocalStore: could not write $name: $e');
    }
  }
}
