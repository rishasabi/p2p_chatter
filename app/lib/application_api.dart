import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'models/chat_message.dart';
import 'models/node_info.dart';
import 'services/api_service.dart';
import 'services/ble_service.dart';
import 'services/chat_store.dart';
import 'services/local_store.dart';
import 'services/settings_store.dart';

/// ApplicationAPI connects the Ember / Chatter UI to both the Go P2P backend
/// (Wi-Fi) and the direct offline Bluetooth layer, and keeps a single view of
/// every peer across the two: who they are (handle) and how they're reachable.
class ApplicationAPI {
  static final ApplicationAPI _instance = ApplicationAPI._internal();
  factory ApplicationAPI() => _instance;

  static final RegExp _handlePattern = RegExp(r'^[A-Za-z0-9._-]+$');

  final ChatterApiService _service;
  final BleService _bleService = BleService();
  Timer? _messagePollTimer;
  Timer? _peerPollTimer;
  Timer? _maintenanceTimer;
  Timer? _saveTimer;
  StreamSubscription<List<NearbyNode>>? _nearbySubscription;
  int _lastMessageId = -1;
  int _lastReceiptId = -1;
  bool _pollingPeers = false;
  bool _pollingMessages = false;
  bool _bridgeRunning = false;
  int _maintenanceTicks = 0;
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  final List<Function(Map<String, dynamic>)> _messageCallbacks = [];
  final List<Function(Map<String, dynamic>)> _peerUpdateCallbacks = [];
  final List<void Function(String peerId)> _historyCallbacks = [];

  String? _myPeerId;
  String? _myHandle;
  List<String> _sharedAddrs = const [];

  /// Everyone we've been connected to, persisted with their handle and last
  /// known Wi-Fi addresses so either transport can find them again later.
  final Map<String, Map<String, dynamic>> _contacts = {};

  /// Peers the Go node currently holds a Wi-Fi (TCP) connection to.
  final Set<String> _wifiPeers = {};

  /// Peers with a live Bluetooth link, keyed by peer ID.
  final Map<String, Map<String, dynamic>> _bluetoothPeers = {};

  /// Chatter phones from recent BLE scans, keyed by advertised peer ID prefix.
  final Map<String, NearbyNode> _nearby = {};
  final Map<String, DateTime> _nearbySince = {};
  final Set<String> _btDialing = {};
  final Set<String> _wifiDialing = {};
  final Map<String, DateTime> _btRetryAt = {};
  final Map<String, DateTime> _wifiRetryAt = {};

  /// Last status published per peer, so listeners only hear about changes.
  final Map<String, String> _publishedStatus = {};

  /// When a peer last reached us through a relay (a message or receipt whose
  /// previous hop wasn't the peer itself).
  final Map<String, DateTime> _relayedSeen = {};

  /// Per-peer chat history (see [ChatStore] for the message shape), kept here
  /// and on disk so nothing is lost while no chat screen is open, or across
  /// restarts. [_messageIndex] finds a message by ID for receipts and dedup.
  final Map<String, List<Map<String, dynamic>>> _history = {};
  final Map<String, Map<String, dynamic>> _messageIndex = {};
  final Set<String> _markingRead = {};
  final ChatStore _chatStore = ChatStore();
  static const _uuid = Uuid();

  Future<void>? _initFuture;

  ApplicationAPI._internal({ChatterApiService? service})
      : _service = service ?? ChatterApiService() {
    _initBluetoothListeners();
    _startPolling();
  }

  // ── Identity ────────────────────────────────────────────────────────────────

  String? get myPeerId => _myPeerId;

  /// This user's handle, bound to [myPeerId]; null until one is chosen.
  String? get myHandle => _myHandle;

  /// Returns why [handle] can't be used, or null if it's fine.
  static String? validateHandle(String handle) {
    final h = handle.trim();
    if (h.length < 3) return 'Use at least 3 characters';
    if (h.length > 20) return 'Use at most 20 characters';
    if (!_handlePattern.hasMatch(h)) return 'Letters, numbers, dot, dash or underscore only';
    return null;
  }

  /// Loads the saved handle and contacts, shares our identity with the
  /// Bluetooth layer and starts background discovery. Safe to call repeatedly.
  Future<void> initialize() {
    return _initFuture ??= _initialize().catchError((Object e) {
      _initFuture = null; // the node may not be up yet; try again next time
      debugPrint('ApplicationAPI initialize failed: $e');
    });
  }

  Future<void> _initialize() async {
    final stored = await LocalStore.read('contacts.json');
    stored.forEach((id, value) {
      if (value is Map) _contacts[id] = Map<String, dynamic>.from(value);
    });
    await _loadHistory();

    final info = await getNode();
    final profile = await LocalStore.read('profile.json');
    // A handle belongs to the identity it was chosen for; a new peer ID
    // (e.g. a reinstall that regenerated the key) means choosing again
    if (profile['peerId'] == info.id && profile['handle'] is String) {
      _myHandle = profile['handle'] as String;
      try {
        await _service.setHandle(_myHandle!);
      } catch (e) {
        debugPrint('Could not share handle with node: $e');
      }
    }
    await _shareIdentity(info);

    if (Platform.isAndroid) {
      _nearbySubscription ??= _bleService.nearbyNodes.listen(_onNearbyNodes);
      if (await _bleService.getBroadcastEnabled()) {
        await setBroadcastEnabled(true);
      }
      unawaited(_runBluetoothBridge());
    }
    _maintenanceTimer ??= Timer.periodic(const Duration(seconds: 3), (_) => _maintainLinks());
    _maintainLinks();
    _publishPeerChanges();
  }

  /// Binds [handle] to this node's peer ID, saves it, and shares it with peers
  /// over Wi-Fi (node profile), Bluetooth (handshake and advertisement) and in
  /// our QR code.
  Future<void> setMyHandle(String handle) async {
    final h = handle.trim();
    final problem = validateHandle(h);
    if (problem != null) throw ArgumentError(problem);

    final info = await getNode();
    _myHandle = h;
    await LocalStore.write('profile.json', {'peerId': info.id, 'handle': h});
    try {
      await _service.setHandle(h);
    } catch (e) {
      debugPrint('Could not share handle with node: $e');
    }
    await _shareIdentity(info);
    if (_bleService.isAdvertising) {
      await _bleService.startAdvertising(info.id, name: h);
    }
  }

  /// Tells the native Bluetooth layer who we are, for handshakes.
  Future<void> _shareIdentity(NodeInfo info) async {
    _myPeerId = info.id;
    _sharedAddrs = info.routableAddrs;
    await _bleService.setLocalIdentity(info.id, name: _myHandle, addrs: _sharedAddrs);
  }

  Future<void> _ensureBluetoothIdentity() async {
    if (_myPeerId != null) return;
    try {
      await _shareIdentity(await getNode());
    } catch (e) {
      debugPrint('Could not set Bluetooth identity: $e');
    }
  }

  /// Turns BLE advertising on or off (persisted). Other phones can only find
  /// and reach us over Bluetooth while it is on.
  Future<bool> setBroadcastEnabled(bool enabled) async {
    if (!enabled) {
      await _bleService.stopAdvertising();
      return false;
    }
    await _ensureBluetoothIdentity();
    final id = _myPeerId;
    if (id == null) return false;
    var name = _myHandle;
    if (name == null || name.isEmpty) {
      name = (await _bleService.getDeviceBluetoothInfo())['name'] ?? 'Chatter';
    }
    return _bleService.startAdvertising(id, name: name);
  }

  // ── Peers ───────────────────────────────────────────────────────────────────

  /// Best name for [peerId]: its handle, else its Bluetooth name, else its ID.
  String displayName(String peerId) {
    final handle = _contacts[peerId]?['handle'] as String?;
    if (handle != null && handle.isNotEmpty) return handle;
    final btName = _bluetoothPeers[peerId]?['name'] as String?;
    if (btName != null && btName.isNotEmpty) return btName;
    return peerId.length > 20 ? '${peerId.substring(0, 16)}…' : peerId;
  }

  /// Current status of one peer: name, and whether it is reachable over
  /// Wi-Fi and/or Bluetooth right now, or recently through a relay.
  Map<String, dynamic> peerStatus(String peerId) {
    final wifi = _wifiPeers.contains(peerId);
    final bt = _bluetoothPeers.containsKey(peerId);
    final relayedAt = _relayedSeen[peerId];
    final mesh = !wifi &&
        !bt &&
        relayedAt != null &&
        DateTime.now().difference(relayedAt) < const Duration(minutes: 2);
    return {
      'id': peerId,
      'name': displayName(peerId),
      'handle': _contacts[peerId]?['handle'],
      'wifi': wifi,
      'bt': bt,
      'mesh': mesh,
      'online': wifi || bt || mesh,
      'unread': unreadCount(peerId),
      'type': wifi && bt
          ? 'WI-FI + BLUETOOTH'
          : wifi
              ? 'WI-FI'
              : bt
                  ? 'BLUETOOTH'
                  : mesh
                      ? 'VIA MESH'
                      : 'OFFLINE',
    };
  }

  /// Full peer ID of a known or linked peer whose ID starts with [prefix]
  /// (as advertised over BLE), or null if we don't know them yet.
  String? peerIdForPrefix(String prefix) =>
      {..._contacts.keys, ..._bluetoothPeers.keys}.where((id) => id.startsWith(prefix)).firstOrNull;

  /// Whether we hold a direct Bluetooth link to [peerId].
  bool isBluetoothLinked(String peerId) => _bluetoothPeers.containsKey(peerId);

  /// Messages from [peerId] we haven't viewed yet.
  int unreadCount(String peerId) =>
      (_history[peerId] ?? const []).where((m) => m['isOutgoing'] != true && m['seen'] != true).length;

  /// Every known peer, reachable ones first.
  List<Map<String, dynamic>> get peers {
    final ids = {..._contacts.keys, ..._wifiPeers, ..._bluetoothPeers.keys};
    return ids.map(peerStatus).toList()
      ..sort((a, b) {
        if (a['online'] != b['online']) return a['online'] == true ? -1 : 1;
        return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
      });
  }

  /// Refreshes Wi-Fi peers from the node and returns every known peer.
  Future<List<Map<String, dynamic>>> getPeers() async {
    await _refreshWifiPeers();
    return peers;
  }

  void _rememberContact(String peerId, {String? handle, List<String>? addrs}) {
    if (peerId.isEmpty || peerId == _myPeerId) return;
    var changed = !_contacts.containsKey(peerId);
    final contact = _contacts.putIfAbsent(peerId, () => <String, dynamic>{});
    if (handle != null && handle.isNotEmpty && contact['handle'] != handle) {
      contact['handle'] = handle;
      changed = true;
    }
    if (addrs != null && addrs.isNotEmpty && !listEquals(contact['addrs'] as List?, addrs)) {
      contact['addrs'] = addrs;
      changed = true;
    }
    if (changed) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), () => LocalStore.write('contacts.json', _contacts));
    }
  }

  /// Notifies listeners about every peer whose status changed.
  void _publishPeerChanges() {
    for (final status in peers) {
      final id = status['id'] as String;
      final signature =
          '${status['name']}|${status['wifi']}|${status['bt']}|${status['mesh']}|${status['unread']}';
      if (_publishedStatus[id] == signature) continue;
      _publishedStatus[id] = signature;
      for (final cb in List.of(_peerUpdateCallbacks)) {
        cb(status);
      }
    }
  }

  Future<void> _refreshWifiPeers() async {
    if (_pollingPeers) return;
    _pollingPeers = true;
    try {
      final peers = await _service.getPeers();
      _wifiPeers
        ..clear()
        ..addAll(peers.map((p) => p.id));
      for (final p in peers) {
        _rememberContact(p.id, handle: p.handle);
      }
      _publishPeerChanges();
    } catch (_) {
      // Node unreachable; keep the last known state
    } finally {
      _pollingPeers = false;
    }
  }

  // ── Bluetooth ───────────────────────────────────────────────────────────────

  void _initBluetoothListeners() {
    _bleService.onBluetoothPeerConnected = (data) {
      final peerId = data['peerId'] as String? ?? '';
      final address = data['address'] as String? ?? '';
      final key = peerId.isNotEmpty ? peerId : address;
      if (key.isEmpty) return;

      // The handshake name is the peer's handle, or its device name if it
      // hasn't picked one (or runs an older build)
      final name = data['name'] as String? ?? '';
      final addrs = (data['addrs'] as List?)?.whereType<String>().toList();
      _bluetoothPeers[key] = {'name': name, 'btAddress': address};
      _btRetryAt.remove(key);
      _nearbySince.remove(key);
      _rememberContact(key, handle: validateHandle(name) == null ? name : null, addrs: addrs);
      unawaited(_syncBluetoothNeighbors());
      _publishPeerChanges();
    };

    // Everything on a Bluetooth link is a mesh frame for the node, which
    // verifies it and either delivers it to us or relays it onward
    _bleService.onBluetoothMessageReceived = (data) {
      final from = data['from'] as String? ?? '';
      final frame = data['content'] as String? ?? '';
      if (from.isEmpty || frame.isEmpty) return;
      _service.bluetoothInbox(from, frame).catchError((Object e) {
        debugPrint('Node rejected Bluetooth frame from $from: $e');
      });
    };

    _bleService.onBluetoothPeerDisconnected = (data) {
      final peerId = data['peerId'] as String? ?? '';
      if (_bluetoothPeers.remove(peerId) != null) {
        unawaited(_syncBluetoothNeighbors());
        _publishPeerChanges();
      }
    };
  }

  /// Tells the node which peers it can reach over our Bluetooth links.
  Future<void> _syncBluetoothNeighbors() async {
    try {
      await _service.setBluetoothPeers(_bluetoothPeers.keys.toList());
    } catch (e) {
      debugPrint('Could not update Bluetooth neighbours: $e');
    }
  }

  /// Carries the node's outgoing frames over our Bluetooth links until
  /// polling stops. Each native send waits for the next phone's ack.
  Future<void> _runBluetoothBridge() async {
    if (_bridgeRunning) return;
    _bridgeRunning = true;
    while (_bridgeRunning) {
      try {
        final frames = await _service.bluetoothOutbox();
        for (final frame in frames) {
          try {
            await _bleService.sendBluetoothMessage(frame.to, frame.data);
          } catch (e) {
            debugPrint('Bluetooth frame to ${frame.to} not delivered: $e');
          }
        }
      } catch (e) {
        await Future.delayed(const Duration(seconds: 1)); // node not up yet
      }
    }
  }

  void _onNearbyNodes(List<NearbyNode> nodes) {
    _nearby
      ..clear()
      ..addEntries(nodes
          .where((n) => n.isChatterPeer && n.psm != null && (n.peerIdPrefix?.length ?? 0) >= 10)
          .map((n) => MapEntry(n.peerIdPrefix!, n)));
    _autoConnectBluetooth();
  }

  NearbyNode? _nearbyNodeFor(String peerId) =>
      _nearby.entries.where((e) => peerId.startsWith(e.key)).map((e) => e.value).firstOrNull;

  /// Links known peers over Bluetooth as soon as they're in range, so there's
  /// a ready fallback when Wi-Fi drops (and no need to tap CONNECT).
  void _autoConnectBluetooth() {
    final me = _myPeerId;
    if (me == null || !Platform.isAndroid) return;
    final now = DateTime.now();
    for (final entry in _nearby.entries) {
      final id = _contacts.keys.where((c) => c.startsWith(entry.key)).firstOrNull;
      if (id == null || _bluetoothPeers.containsKey(id) || _btDialing.contains(id)) continue;
      if (now.isBefore(_btRetryAt[id] ?? now)) continue;
      // Both phones usually see each other: the lower peer ID dials, and the
      // other side only steps in if no link appears within a few seconds
      final since = _nearbySince.putIfAbsent(id, () => now);
      if (me.compareTo(id) > 0 && now.difference(since) < const Duration(seconds: 8)) continue;
      unawaited(_dialBluetooth(id, entry.value));
    }
  }

  Future<bool> _dialBluetooth(String peerId, NearbyNode node) async {
    _btDialing.add(peerId);
    try {
      await connectBluetooth(node.id, peerId: node.peerIdPrefix, psm: node.psm);
      // The link counts once the handshake names the peer
      final linked = await _waitFor(() => _bluetoothPeers.containsKey(peerId), const Duration(seconds: 4));
      if (!linked) _btRetryAt[peerId] = DateTime.now().add(const Duration(seconds: 15));
      return linked;
    } catch (e) {
      debugPrint('Bluetooth link to $peerId failed: $e');
      _btRetryAt[peerId] = DateTime.now().add(const Duration(seconds: 15));
      return false;
    } finally {
      _btDialing.remove(peerId);
    }
  }

  /// Makes sure there's a Bluetooth link to [peerId], scanning briefly if it
  /// hasn't been seen nearby yet (unless [scan] is false). Returns whether a
  /// link is up.
  Future<bool> _linkBluetooth(String peerId, {bool scan = true}) async {
    if (_bluetoothPeers.containsKey(peerId)) return true;
    if (!Platform.isAndroid) return false;
    if (_btDialing.contains(peerId)) {
      return _waitFor(() => _bluetoothPeers.containsKey(peerId), const Duration(seconds: 5));
    }
    var node = _nearbyNodeFor(peerId);
    if (node == null && scan) {
      _lastScanAt = DateTime.now();
      unawaited(_bleService.startScan(timeout: const Duration(seconds: 8)));
      await _waitFor(() => _nearbyNodeFor(peerId) != null, const Duration(seconds: 6));
      node = _nearbyNodeFor(peerId);
    }
    return node != null && await _dialBluetooth(peerId, node);
  }

  /// Connect directly to a device over Bluetooth (LE L2CAP if [psm] is known,
  /// otherwise RFCOMM)
  Future<bool> connectBluetooth(String address, {String? peerId, int? psm}) async {
    await _ensureBluetoothIdentity();
    return _bleService.connectBluetooth(address, peerId: peerId, psm: psm);
  }

  /// Resolves to the full peer ID once a Bluetooth handshake with a peer whose
  /// ID starts with [prefix] completes, or null after [timeout].
  Future<String?> waitForBluetoothPeer(String prefix,
      {Duration timeout = const Duration(seconds: 4)}) async {
    String? match() => _bluetoothPeers.keys.where((id) => id.startsWith(prefix)).firstOrNull;
    await _waitFor(() => match() != null, timeout);
    return match();
  }

  static Future<bool> _waitFor(bool Function() condition, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return true;
  }

  // ── Background upkeep ───────────────────────────────────────────────────────

  void _maintainLinks() {
    _maintenanceTicks++;
    _autoConnectBluetooth();
    _reconnectWifi();

    // Scan while some known peer isn't linked over Bluetooth yet
    final now = DateTime.now();
    final unlinked = _contacts.keys.any((id) => !_bluetoothPeers.containsKey(id));
    if (Platform.isAndroid && unlinked && now.difference(_lastScanAt) > const Duration(seconds: 20)) {
      _lastScanAt = now;
      unawaited(_bleService.startScan(timeout: const Duration(seconds: 8)));
    }

    // Our Wi-Fi address can change (new network, DHCP); keep handshakes current
    if (_maintenanceTicks % 10 == 0) unawaited(_refreshOwnAddrs());

    // Read receipts that couldn't be delivered when the chat was viewed
    if (_maintenanceTicks % 10 == 5) {
      for (final peerId in _history.keys.toList()) {
        if (peerStatus(peerId)['online'] == true) unawaited(_sendPendingReadReceipts(peerId));
      }
    }

    // Keep the node's view of our Bluetooth links right even if it restarted,
    // and let "via mesh" statuses expire
    if (Platform.isAndroid) unawaited(_syncBluetoothNeighbors());
    _publishPeerChanges();
  }

  /// Moves known peers back onto Wi-Fi when it's available, using the
  /// addresses learned from their QR code or Bluetooth handshake.
  void _reconnectWifi() {
    final now = DateTime.now();
    for (final entry in _contacts.entries) {
      final id = entry.key;
      final addrs = (entry.value['addrs'] as List?)?.whereType<String>().toList() ?? const <String>[];
      if (addrs.isEmpty || _wifiPeers.contains(id) || _wifiDialing.contains(id)) continue;
      if (now.isBefore(_wifiRetryAt[id] ?? now)) continue;
      _wifiRetryAt[id] = now.add(const Duration(seconds: 30));
      _wifiDialing.add(id);
      _service
          .connectPeer(jsonEncode({'id': id, 'addrs': addrs}))
          .then((_) => _refreshWifiPeers())
          .catchError((Object _) {}) // still unreachable; retry later
          .whenComplete(() => _wifiDialing.remove(id));
    }
  }

  Future<void> _refreshOwnAddrs() async {
    try {
      final info = await getNode();
      if (!listEquals(info.routableAddrs, _sharedAddrs)) await _shareIdentity(info);
    } catch (_) {}
  }

  // ── Messages ────────────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    final stored = await _chatStore.loadAll();
    stored.forEach((peerId, messages) {
      final list = _history.putIfAbsent(peerId, () => []);
      for (final m in messages) {
        if (_messageIndex.containsKey(m['id'])) continue;
        // The app closed mid-send, so we can't know whether it went out
        if (m['status'] == 'sending') {
          m['status'] = 'failed';
          unawaited(_chatStore.save(m));
        }
        _messageIndex[m['id'] as String] = m;
        list.add(m);
      }
      list.sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));
      _notifyHistory(peerId);
    });
  }

  void _addMessage(Map<String, dynamic> message) {
    final peerId = message['peerId'] as String;
    _messageIndex[message['id'] as String] = message;
    _history.putIfAbsent(peerId, () => []).add(message);
    unawaited(_chatStore.save(message));
    _notifyHistory(peerId);
  }

  static const _statusRank = {'failed': 0, 'sending': 1, 'sent': 2, 'delivered': 3, 'read': 4};

  /// Moves an outgoing message forward to [status] (never backwards: a late
  /// "sent" must not undo a receipt that already arrived).
  void _advanceStatus(Map<String, dynamic> message, String status) {
    if ((_statusRank[status] ?? 0) <= (_statusRank[message['status']] ?? 0)) return;
    message['status'] = status;
    unawaited(_chatStore.save(message));
    _notifyHistory(message['peerId'] as String);
  }

  void _notifyHistory(String peerId) {
    for (final cb in List.of(_historyCallbacks)) {
      cb(peerId);
    }
    _publishPeerChanges(); // unread counts
  }

  /// A message the node delivered to us: over Wi-Fi, Bluetooth, or relayed.
  void _dispatchIncoming(ChatMessage msg) {
    final id = msg.msgId ?? 'node-${msg.id}-${msg.timestamp.millisecondsSinceEpoch}';
    if (_messageIndex.containsKey(id)) return; // already have it, e.g. refetched after a restart
    final handle = msg.handle;
    _rememberContact(msg.from, handle: handle != null && validateHandle(handle) == null ? handle : null);
    if (msg.isRelayed) _relayedSeen[msg.from] = DateTime.now();
    _addMessage({
      'id': id,
      'peerId': msg.from,
      'content': msg.content,
      'isOutgoing': false,
      'timestamp': msg.timestamp,
      'status': 'received',
      'seen': false,
      'readSent': false,
    });
    for (final cb in List.of(_messageCallbacks)) {
      cb({'id': id, 'from': msg.from, 'content': msg.content, 'timestamp': msg.timestamp.toIso8601String()});
    }
  }

  void _applyReceipt(Receipt receipt) {
    if (receipt.isRelayed) _relayedSeen[receipt.from] = DateTime.now();
    for (final id in receipt.ids) {
      final message = _messageIndex[id];
      // Only the peer the message went to can confirm it
      if (message == null || message['isOutgoing'] != true || message['peerId'] != receipt.from) continue;
      _advanceStatus(message, receipt.status == 'read' ? 'read' : 'delivered');
    }
  }

  @visibleForTesting
  void receiveFromNode(ChatMessage msg) => _dispatchIncoming(msg);

  @visibleForTesting
  void receiveReceiptFromNode(Receipt receipt) => _applyReceipt(receipt);

  /// Messages exchanged with [peerId] so far, oldest first. See [ChatStore]
  /// for the shape of each message.
  List<Map<String, dynamic>> historyFor(String peerId) =>
      List.unmodifiable(_history[peerId] ?? const []);

  /// Called with a peer ID whenever that conversation changes: new messages,
  /// status ticks, or messages marked read.
  void onHistoryChanged(void Function(String peerId) callback) {
    if (!_historyCallbacks.contains(callback)) _historyCallbacks.add(callback);
  }

  void removeOnHistoryChanged(void Function(String peerId) callback) {
    _historyCallbacks.remove(callback);
  }

  /// Marks [peerId]'s messages as seen and, if read receipts are on, tells
  /// the sender (relayed if need be). Call while their chat is on screen.
  Future<void> markRead(String peerId) async {
    var changed = false;
    for (final m in _history[peerId] ?? const <Map<String, dynamic>>[]) {
      if (m['isOutgoing'] != true && m['seen'] != true) {
        m['seen'] = true;
        unawaited(_chatStore.save(m));
        changed = true;
      }
    }
    if (changed) _notifyHistory(peerId);
    await _sendPendingReadReceipts(peerId);
  }

  /// Sends read receipts for seen messages the sender hasn't heard about yet;
  /// ones that can't be delivered now are retried later.
  Future<void> _sendPendingReadReceipts(String peerId) async {
    final pending = (_history[peerId] ?? const <Map<String, dynamic>>[])
        .where((m) => m['isOutgoing'] != true && m['seen'] == true && m['readSent'] != true)
        .toList();
    if (pending.isEmpty || !_markingRead.add(peerId)) return;
    try {
      if (SettingsStore().getBool(SettingsStore.readReceipts, fallback: true)) {
        await _service.sendReceipt(peerId, [for (final m in pending) m['id'] as String], 'read');
      }
      for (final m in pending) {
        m['readSent'] = true;
        unawaited(_chatStore.save(m));
      }
    } catch (e) {
      debugPrint('Read receipt to $peerId not sent yet: $e');
    } finally {
      _markingRead.remove(peerId);
    }
  }

  void _startPolling() {
    // Poll the local node every second: new messages and receipts, and which
    // peers it is connected to (it drops unresponsive peers within seconds)
    _messagePollTimer?.cancel();
    _messagePollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollNode());

    _peerPollTimer?.cancel();
    _peerPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshWifiPeers());
  }

  Future<void> _pollNode() async {
    if (_pollingMessages) return;
    _pollingMessages = true;
    try {
      for (final msg in await _service.getMessages(afterId: _lastMessageId)) {
        if (msg.id > _lastMessageId) _lastMessageId = msg.id;
        _dispatchIncoming(msg);
      }
      for (final receipt in await _service.getReceipts(afterId: _lastReceiptId)) {
        if (receipt.id > _lastReceiptId) _lastReceiptId = receipt.id;
        _applyReceipt(receipt);
      }
    } catch (_) {
      // Node unreachable; try again next tick
    } finally {
      _pollingMessages = false;
    }
  }

  /// Backend service accessor
  ChatterApiService get service => _service;

  /// Check backend health status
  Future<bool> checkHealth() => _service.checkHealth();

  /// Retrieve this node's ID and multiaddrs
  Future<NodeInfo> getNode() async {
    final info = await _service.getNode();
    if (info.hasRoutableAddrs) return info;

    // Go can't list network interfaces on Android 11+ (netlink is restricted),
    // so the node reports only loopback. Add this device's LAN IPs ourselves.
    final port = RegExp(r'/tcp/(\d+)/').firstMatch(info.addrs.join(' '))?.group(1);
    if (port == null) return info;
    final lanAddrs = <String>[];
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final a in iface.addresses) {
          if (!a.isLoopback && !a.isLinkLocal) {
            lanAddrs.add('/ip4/${a.address}/tcp/$port/p2p/${info.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('Could not list network interfaces: $e');
    }
    return NodeInfo(id: info.id, addrs: [...lanAddrs, ...info.addrs]);
  }

  /// Connect to a peer from a scanned code: the JSON QR payload, a multiaddr,
  /// or a Bluetooth MAC. Returns the peer's ID when the code names it.
  Future<String?> connectPeer(String addressInput) async {
    final clean = addressInput.trim();
    if (clean.isEmpty) return null;

    // Check if it's a Bluetooth connection string:
    // e.g. "chatter://bt/<mac>?peerId=..." or a raw MAC address like "AA:BB:CC:DD:EE:FF"
    final macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');

    if (clean.startsWith('chatter://bt/')) {
      final uri = Uri.parse(clean);
      final mac = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : uri.host;
      final peerId = uri.queryParameters['peerId'] ?? '';
      await connectBluetooth(mac, peerId: peerId);
      return peerId.isNotEmpty ? await waitForBluetoothPeer(peerId) : null;
    }

    if (macRegex.hasMatch(clean)) {
      await connectBluetooth(clean);
      return null;
    }

    String? peerId;
    if (clean.startsWith('{')) {
      // JSON QR payload: {"id", "name" (handle), "addrs", optional "bt"}
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(clean) as Map<String, dynamic>;
      } catch (_) {}
      peerId = data?['id'] as String?;
      final name = data?['name'] as String? ?? '';
      final addrs = (data?['addrs'] as List?)?.whereType<String>().toList() ?? const <String>[];
      if (peerId != null && peerId.isNotEmpty) {
        _rememberContact(peerId, handle: validateHandle(name) == null ? name : null, addrs: addrs);
      }

      final btMac = data?['bt'] as String? ?? '';
      if (btMac.isNotEmpty && btMac != '02:00:00:00:00:00') {
        try {
          await connectBluetooth(btMac, peerId: peerId);
          return peerId;
        } catch (e) {
          if (addrs.isEmpty) rethrow;
          debugPrint('Bluetooth connect failed ($e), trying TCP addrs...');
        }
      }
    } else {
      peerId = RegExp(r'/p2p/([A-Za-z0-9]+)').firstMatch(clean)?.group(1);
      if (peerId != null) _rememberContact(peerId, addrs: [clean]);
    }

    // Connect via Go libp2p over Wi-Fi (the backend also accepts the JSON
    // {"id", "addrs"} QR payload and dials every address)
    try {
      await _service.connectPeer(clean);
    } catch (e) {
      // Wi-Fi can't reach them (it's down, or a different network), but the
      // code still says who they are: reach them over Bluetooth instead
      final id = peerId;
      if (id == null || !await _linkBluetooth(id)) rethrow;
      debugPrint('Wi-Fi connect failed ($e); linked $id over Bluetooth');
      return id;
    }
    await _refreshWifiPeers();
    return peerId;
  }

  /// Sends [msg] to [peerId] by the best path the node has: Wi-Fi, a
  /// Bluetooth link, or relayed through other peers when there's no direct
  /// link. Its status goes sending → sent, then delivered and read as
  /// receipts come back; failed if no path exists right now.
  Future<void> sendMessage(String msg, String peerId) async {
    final message = <String, dynamic>{
      'id': _uuid.v4(),
      'peerId': peerId,
      'content': msg,
      'isOutgoing': true,
      'timestamp': DateTime.now(),
      'status': 'sending',
      'seen': true,
      'readSent': false,
    };
    _addMessage(message);
    try {
      // A direct Bluetooth link beats a relay when the peer is close by
      if (!_wifiPeers.contains(peerId) && !_bluetoothPeers.containsKey(peerId)) {
        await _linkBluetooth(peerId, scan: false);
      }
      if (Platform.isAndroid) await _syncBluetoothNeighbors();
      await _service.sendChat(peerId, msg, id: message['id'] as String);
      _advanceStatus(message, 'sent');
    } catch (e) {
      // A receipt may already have proven it arrived; only an unconfirmed send failed
      if (message['status'] == 'sending') {
        message['status'] = 'failed';
        unawaited(_chatStore.save(message));
        _notifyHistory(peerId);
      }
      if (e is ApiException && e.message.contains('no connected peers')) {
        throw ApiException('${displayName(peerId)} is out of reach: no Wi-Fi, Bluetooth or relay path right now');
      }
      rethrow;
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
    _bridgeRunning = false;
    _messagePollTimer?.cancel();
    _peerPollTimer?.cancel();
    _maintenanceTimer?.cancel();
    _saveTimer?.cancel();
    _messagePollTimer = null;
    _peerPollTimer = null;
    _maintenanceTimer = null;
    _saveTimer = null;
  }

  void dispose() {
    stopPolling();
    _nearbySubscription?.cancel();
    _service.dispose();
  }
}
