import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'local_store.dart';

/// Chat history on disk (SQLite): one row per message, keyed by message ID.
///
/// Messages are maps with: id, peerId, content, isOutgoing, timestamp
/// (DateTime), status (sending | sent | delivered | read | failed | received),
/// seen (we've viewed it) and readSent (the sender has been told we read it).
class ChatStore {
  static final ChatStore _instance = ChatStore._();
  factory ChatStore() => _instance;
  ChatStore._();

  Database? _db;

  Future<Database?> _open() async {
    // sqflite needs a platform plugin, which unit tests don't have
    if (LocalStore.isTestMode) return null;
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'chatter.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            peer_id TEXT NOT NULL,
            outgoing INTEGER NOT NULL,
            content TEXT NOT NULL,
            ts INTEGER NOT NULL,
            status TEXT NOT NULL,
            seen INTEGER NOT NULL DEFAULT 0,
            read_sent INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('CREATE INDEX messages_by_peer ON messages(peer_id, ts)');
      },
    );
  }

  /// Every stored message, grouped by peer, oldest first.
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    final out = <String, List<Map<String, dynamic>>>{};
    try {
      final db = await _open();
      if (db == null) return out;
      for (final row in await db.query('messages', orderBy: 'ts')) {
        final message = _fromRow(row);
        out.putIfAbsent(message['peerId'] as String, () => []).add(message);
      }
    } catch (e) {
      debugPrint('ChatStore: could not load messages: $e');
    }
    return out;
  }

  /// Inserts [message], or updates it if one with the same ID exists.
  Future<void> save(Map<String, dynamic> message) async {
    try {
      final db = await _open();
      await db?.insert('messages', _toRow(message), conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('ChatStore: could not save message: $e');
    }
  }

  static Map<String, Object?> _toRow(Map<String, dynamic> m) => {
        'id': m['id'],
        'peer_id': m['peerId'],
        'outgoing': m['isOutgoing'] == true ? 1 : 0,
        'content': m['content'] ?? '',
        'ts': (m['timestamp'] as DateTime).millisecondsSinceEpoch,
        'status': m['status'] ?? 'received',
        'seen': m['seen'] == true ? 1 : 0,
        'read_sent': m['readSent'] == true ? 1 : 0,
      };

  static Map<String, dynamic> _fromRow(Map<String, Object?> r) => {
        'id': r['id'],
        'peerId': r['peer_id'],
        'isOutgoing': r['outgoing'] == 1,
        'content': r['content'],
        'timestamp': DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
        'status': r['status'],
        'seen': r['seen'] == 1,
        'readSent': r['read_sent'] == 1,
      };
}
