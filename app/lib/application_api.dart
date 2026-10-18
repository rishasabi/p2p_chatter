import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'models/node_info.dart';
import 'services/api_service.dart';
import 'services/ble_service.dart';

/// ApplicationAPI connects the Ember / Chatter UI to both the Go P2P backend
/// and the direct offline Bluetooth RFCOMM mesh layer.
class ApplicationAPI {
  static final ApplicationAPI _instance = ApplicationAPI._internal();
  factory ApplicationAPI() => _instance;

  final ChatterApiService _service;
  final BleService _bleService = BleService();
  Timer? _messagePollTimer;
  Timer? _peerPollTimer;
  int _lastMessageId = -1;

  final List<Function(Map<String, dynamic>)> _messageCallbacks = [];
  final List<Function(Map<String, dynamic>)> _peerUpdateCallbacks = [];

  List<Map<String, dynamic>> _cachedPeers = [];
  final Map<String, Map<String, dynamic>> _bluetoothPeers = {};

  ApplicationAPI._internal({ChatterApiService? service})
      : _service = service ?? ChatterApiService() {
    _initBluetoothListeners();
    _startPolling();
  }

  void _initBluetoothListeners() {
    _bleService.onBluetoothPeerConnected = (data) {
      final peerId = data['peerId'] as String? ?? '';
      final name = data['name'] as String? ?? 'Bluetooth Peer';
      final address = data['address'] as String? ?? '';
      final key = peerId.isNotEmpty ? peerId : address;

      if (key.isNotEmpty) {
        final peerMap = {
          'id': key,
          'name': name,
          'type': 'BLUETOOTH',
          'online': true,
          'btAddress': address,
        };
        _bluetoothPeers[key] = peerMap;
        _notifyPeerUpdate(peerMap);
      }
    };

    _bleService.onBluetoothMessageReceived = (data) {
      for (final cb in _messageCallbacks) {
        cb(data);
      }
    };

    _bleService.onBluetoothPeerDisconnected = (data) {
      final peerId = data['peerId'] as String? ?? '';
      if (peerId.isNotEmpty && _bluetoothPeers.containsKey(peerId)) {
        _bluetoothPeers[peerId]!['online'] = false;
        _notifyPeerUpdate(_bluetoothPeers[peerId]!);
      }
    };
  }

  void _notifyPeerUpdate(Map<String, dynamic> peer) {
    for (final cb in _peerUpdateCallbacks) {
      cb(peer);
    }
  }

  void _startPolling() {
    // Poll incoming messages from the Go backend every 2 seconds
    _messagePollTimer?.cancel();
    _messagePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final messages = await _service.getMessages(afterId: _lastMessageId);
        for (final msg in messages) {
          if (msg.id > _lastMessageId) {
            _lastMessageId = msg.id;
          }
          final map = {
            'id': msg.id,
            'from': msg.from,
            'content': msg.content,
            'timestamp': msg.timestamp.toIso8601String(),
          };
          for (final cb in _messageCallbacks) {
            cb(map);
          }
        }
      } catch (_) {}
    });

    // Poll connected peers every 3 seconds
    _peerPollTimer?.cancel();
    _peerPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final peers = await _service.getPeers();
        final mapped = peers
            .map((p) => {
                  'id': p.id,
                  'name': p.shortId,
                  'type': 'DIRECT P2P',
                  'online': true,
                })
            .toList();

        // Merge Go backend peers with Bluetooth peers
        final allPeers = <Map<String, dynamic>>[];
        final seen = <String>{};

        for (final bp in _bluetoothPeers.values) {
          allPeers.add(bp);
          seen.add(bp['id'] as String);
        }

        for (final p in mapped) {
          final pid = p['id'] as String;
          if (!seen.contains(pid)) {
            allPeers.add(p);
            seen.add(pid);
          }
        }

        _cachedPeers = allPeers;
        for (final p in _cachedPeers) {
          _notifyPeerUpdate(p);
        }
      } catch (_) {}
    });
  }

  /// Backend service accessor
  ChatterApiService get service => _service;

  /// Check backend health status
  Future<bool> checkHealth() => _service.checkHealth();

  /// Retrieve this node's ID and multiaddrs
  Future<NodeInfo> getNode() => _service.getNode();

  /// Connect to a remote peer via Bluetooth or TCP multiaddr
  Future<void> connectPeer(String addressInput) async {
    final clean = addressInput.trim();
    if (clean.isEmpty) return;

    // Check if it's a Bluetooth connection string:
    // e.g. "chatter://bt/<mac>?peerId=..." or a raw MAC address like "AA:BB:CC:DD:EE:FF"
    final macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');

    if (clean.startsWith('chatter://bt/')) {
      final uri = Uri.parse(clean);
      final mac = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.host;
      final peerId = uri.queryParameters['peerId'] ?? '';
      await _bleService.connectBluetooth(mac, peerId: peerId);
      return;
    }

    if (macRegex.hasMatch(clean)) {
      await _bleService.connectBluetooth(clean);
      return;
    }

    // Check if input is a JSON payload with Bluetooth info
    if (clean.startsWith('{')) {
      try {
        final data = jsonDecode(clean) as Map<String, dynamic>;
        final btMac = data['bt'] as String? ?? '';
        final peerId = data['id'] as String? ?? '';
        if (btMac.isNotEmpty && btMac != '02:00:00:00:00:00') {
          await _bleService.connectBluetooth(btMac, peerId: peerId);
          return;
        }
      } catch (_) {}
    }

    // Otherwise connect via Go libp2p TCP multiaddr
    await _service.connectPeer(clean);
  }

  /// Send message to peer - prioritizes Bluetooth when available
  Future<void> sendMessage(String msg, String peerId) async {
    // 1. If peer is connected via Bluetooth, send via Bluetooth RFCOMM
    if (_bluetoothPeers.containsKey(peerId) || _bluetoothPeers.values.any((p) => p['btAddress'] == peerId)) {
      try {
        final sent = await _bleService.sendBluetoothMessage(peerId, msg);
        if (sent) return;
      } catch (e) {
        debugPrint('Bluetooth send failed ($e), falling back to TCP...');
      }
    }

    // 2. Otherwise send via Go backend POST /message
    try {
      await _service.sendMessage(peerId, msg);
    } catch (e) {
      // Also attempt Bluetooth broadcast if TCP fails
      try {
        final sent = await _bleService.sendBluetoothMessage(peerId, msg);
        if (sent) return;
      } catch (_) {}
      rethrow;
    }
  }

  /// Show peer status / Contacts list (combines Bluetooth + TCP peers)
  Future<List<Map<String, dynamic>>> getPeers() async {
    try {
      final peers = await _service.getPeers();
      final mapped = peers
          .map((p) => {
                'id': p.id,
                'name': p.shortId,
                'type': 'DIRECT P2P',
                'online': true,
              })
          .toList();

      final allPeers = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final bp in _bluetoothPeers.values) {
        allPeers.add(bp);
        seen.add(bp['id'] as String);
      }

      for (final p in mapped) {
        final pid = p['id'] as String;
        if (!seen.contains(pid)) {
          allPeers.add(p);
          seen.add(pid);
        }
      }

      _cachedPeers = allPeers;
      return _cachedPeers;
    } catch (_) {
      return _cachedPeers;
    }
  }

  /// Register callback for incoming messages
  void onMessage(Function(Map<String, dynamic>) callback) {
    if (!_messageCallbacks.contains(callback)) {
      _messageCallbacks.add(callback);
    }
  }

  /// Unregister message callback
  void removeOnMessage(Function(Map<String, dynamic>) callback) {
    _messageCallbacks.remove(callback);
  }

  /// Register callback for peer state updates
  void onPeerUpdate(Function(Map<String, dynamic>) callback) {
    if (!_peerUpdateCallbacks.contains(callback)) {
      _peerUpdateCallbacks.add(callback);
    }
  }

  /// Unregister peer update callback
  void removeOnPeerUpdate(Function(Map<String, dynamic>) callback) {
    _peerUpdateCallbacks.remove(callback);
  }

  void stopPolling() {
    _messagePollTimer?.cancel();
    _peerPollTimer?.cancel();
    _messagePollTimer = null;
    _peerPollTimer = null;
  }

  void dispose() {
    stopPolling();
    _service.dispose();
  }
}