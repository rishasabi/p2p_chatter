import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/node_info.dart';
import '../models/peer.dart';

/// HTTP client for the Go p2p-chat backend.
///
/// All methods throw [ApiException] on non-2xx responses or network errors.
class ChatterApiService {
  final String baseUrl;
  final http.Client _client;

  /// Default backend URL:
  /// - Overridable via `--dart-define=API_URL=http://<host>:<port>`
  /// - Defaults to `http://localhost:8080`
  static String get defaultUrl {
    const envUrl = String.fromEnvironment('API_URL');
    if (envUrl.isNotEmpty) return envUrl;
    return 'http://localhost:8080';
  }

  ChatterApiService({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? defaultUrl,
        _client = client ?? http.Client();

  // ── Health ──────────────────────────────────────────────────────────────────

  /// Returns `true` if the backend is reachable and healthy.
  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['status'] == 'ok';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Node ────────────────────────────────────────────────────────────────────

  /// Fetches this node's peer ID and multiaddrs.
  Future<NodeInfo> getNode() async {
    final response = await _get('/node');
    return NodeInfo.fromJson(response);
  }

  /// Sets this node's handle; the node shares it with every peer it connects to.
  Future<void> setHandle(String handle) async {
    await _post('/profile', {'handle': handle});
  }

  // ── Peers ───────────────────────────────────────────────────────────────────

  /// Returns the list of currently connected peers.
  Future<List<Peer>> getPeers() async {
    final body = await _get('/peers');
    final list = body['peers'] as List? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(Peer.fromJson)
        .toList();
  }

  /// Dials a remote peer by its full multiaddr string.
  ///
  /// Example: `/ip4/192.168.1.5/tcp/4001/p2p/12D3KooW...`
  Future<void> connectPeer(String address) async {
    await _post('/peers/connect', {'address': address});
  }

  // ── Messages ─────────────────────────────────────────────────────────────────

  /// Sends a text message to [peerId].
  Future<void> sendMessage(String peerId, String content) async {
    await _post('/message', {'peer_id': peerId, 'content': content});
  }

  /// Returns messages received after [afterId].
  ///
  /// Pass `afterId: -1` (default) to fetch all messages.
  Future<List<ChatMessage>> getMessages({int afterId = -1}) async {
    final uri = Uri.parse('$baseUrl/messages').replace(
      queryParameters: {'after': afterId.toString()},
    );
    final response = await _rawGet(uri);
    final list = response['messages'] as List? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  /// Sends [content] to [peerId] under message ID [id]. The node relays it
  /// through other peers when there's no direct link. Returns the ID used.
  Future<String> sendChat(String peerId, String content, {String? id}) async {
    final body = await _post('/message', {
      'peer_id': peerId,
      'content': content,
      if (id != null) 'id': id,
    });
    return body['id'] as String? ?? id ?? '';
  }

  // ── Receipts ─────────────────────────────────────────────────────────────────

  /// Receipts from peers for messages we sent, after [afterId].
  Future<List<Receipt>> getReceipts({int afterId = -1}) async {
    final uri = Uri.parse('$baseUrl/receipts').replace(
      queryParameters: {'after': afterId.toString()},
    );
    final response = await _rawGet(uri);
    final list = response['receipts'] as List? ?? [];
    return list.cast<Map<String, dynamic>>().map(Receipt.fromJson).toList();
  }

  /// Tells [peerId] that we received or read the messages [ids].
  Future<void> sendReceipt(String peerId, List<String> ids, String status) async {
    await _post('/receipts', {'peer_id': peerId, 'ids': ids, 'status': status});
  }

  // ── Bluetooth bridge ─────────────────────────────────────────────────────────
  // The node routes over Bluetooth links that live in the app: we report our
  // Bluetooth neighbours, carry its outgoing frames, and hand in received ones.

  Future<void> setBluetoothPeers(List<String> peerIds) async {
    await _post('/bt/peers', {'peers': peerIds});
  }

  /// Waits up to [wait] for frames to send over Bluetooth. Each frame's data
  /// is base64 and is passed through untouched.
  Future<List<({String to, String data})>> bluetoothOutbox(
      {Duration wait = const Duration(seconds: 20)}) async {
    final uri = Uri.parse('$baseUrl/bt/outbox').replace(
      queryParameters: {'wait': wait.inSeconds.toString()},
    );
    final response = await _rawGet(uri, timeout: wait + const Duration(seconds: 5));
    final list = response['frames'] as List? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map((f) => (to: f['to'] as String, data: f['data'] as String))
        .toList();
  }

  /// Hands the node a frame (base64 [data]) received from Bluetooth neighbour [from].
  Future<void> bluetoothInbox(String from, String data) async {
    await _post('/bt/inbox', {'from': from, 'data': data});
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    return _rawGet(Uri.parse('$baseUrl$path'));
  }

  Future<Map<String, dynamic>> _rawGet(Uri uri,
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final response = await _client
          .get(uri)
          .timeout(timeout);
      _assertOk(response);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      _assertOk(response);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  void _assertOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'HTTP ${response.statusCode}: ${response.body.trim()}',
        statusCode: response.statusCode,
      );
    }
  }

  void dispose() => _client.close();
}

/// Thrown when the API returns an error or is unreachable.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message';
}
