import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_store.dart';

/// Unsent text per conversation (a peer ID, or a channel's conversation ID),
/// kept while the user is elsewhere and across restarts in drafts.json.
/// [load] once at startup; reads are synchronous after that. Listeners hear
/// about every change, e.g. so the Chats list can show "Draft:".
class DraftStore extends ChangeNotifier {
  static final DraftStore _instance = DraftStore._();
  factory DraftStore() => _instance;
  DraftStore._();

  final Map<String, String> _drafts = {};
  Timer? _saveTimer;

  Future<void> load() async {
    final stored = await LocalStore.read('drafts.json');
    stored.forEach((id, text) {
      if (text is String && text.trim().isNotEmpty) _drafts[id] = text;
    });
  }

  /// The draft for [conversationId], or '' if there is none.
  String getDraft(String conversationId) => _drafts[conversationId] ?? '';

  bool hasDraft(String conversationId) => _drafts.containsKey(conversationId);

  /// Keeps [text] as the draft; whitespace alone counts as no draft.
  void setDraft(String conversationId, String text) {
    if (text.trim().isEmpty) {
      clearDraft(conversationId);
      return;
    }
    if (_drafts[conversationId] == text) return;
    _drafts[conversationId] = text;
    _changed();
  }

  void clearDraft(String conversationId) {
    if (_drafts.remove(conversationId) != null) _changed();
  }

  // Kept in memory at once, so nothing typed is lost if the screen closes;
  // written to disk once typing pauses
  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), flush);
  }

  /// Writes pending changes now, e.g. before the app is closed.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await LocalStore.write('drafts.json', Map.of(_drafts));
  }
}
