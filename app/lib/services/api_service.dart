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

  // ── Private helpers ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    return _rawGet(Uri.parse('$baseUrl$path'));
  }

  Future<Map<String, dynamic>> _rawGet(Uri uri) async {
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
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
    Map<String, String> body,
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
