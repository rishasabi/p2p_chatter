import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class NearbyNode {
  final String id;
  final String name;
  final int rssi;
  final String? multiaddr;
  final bool isChatterPeer;

  /// LE L2CAP PSM advertised by a Chatter peer. [id] is a private BLE address
  /// that RFCOMM can't reach, so connections to Chatter peers go through this.
  final int? psm;

  /// Leading characters of the peer's libp2p ID, from its advertisement.
  final String? peerIdPrefix;

  const NearbyNode({
    required this.id,
    required this.name,
    required this.rssi,
    this.multiaddr,
    this.isChatterPeer = false,
    this.psm,
    this.peerIdPrefix,
  });

  bool get isP2pCapable => isChatterPeer || (multiaddr != null && multiaddr!.isNotEmpty);

  String get signalStrength {
    if (rssi >= -50) return 'EXCELLENT';
    if (rssi >= -65) return 'GOOD';
    if (rssi >= -80) return 'FAIR';
    return 'WEAK';
  }
}

/// BleService manages Bluetooth Low Energy (BLE) scanning, native advertising,
/// and direct RFCOMM Bluetooth peer-to-peer data communication.
class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;

  static const MethodChannel _advertiserChannel =
      MethodChannel('com.example.app/ble_advertiser');

  static final Guid _chatterGuid = Guid('0000ff01-0000-1000-8000-00805f9b34fb');
  // Scan-response service data carrying the advertiser's handle
  static final Guid _handleGuid = Guid('0000ff02-0000-1000-8000-00805f9b34fb');
  static const Duration _nearbyTtl = Duration(seconds: 30);

  bool _isAdvertising = false;
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  // Devices from recent scans and when each was last seen, so the list doesn't
  // empty out every time a new scan starts
  final Map<String, (NearbyNode, DateTime)> _seenNodes = {};
  final StreamController<List<NearbyNode>> _nearbyNodesController =
      StreamController<List<NearbyNode>>.broadcast();

  // Callbacks for Bluetooth events
  Function(Map<String, dynamic>)? onBluetoothMessageReceived;
  Function(Map<String, dynamic>)? onBluetoothPeerConnected;
  Function(Map<String, dynamic>)? onBluetoothPeerDisconnected;

  Stream<List<NearbyNode>> get nearbyNodes => _nearbyNodesController.stream;
  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;

  BleService._internal() {
    _advertiserChannel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onBluetoothPeerConnected':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        debugPrint('BLE onBluetoothPeerConnected: $data');
        onBluetoothPeerConnected?.call(data);
        break;
      case 'onBluetoothMessageReceived':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        debugPrint('BLE onBluetoothMessageReceived: $data');
        onBluetoothMessageReceived?.call(data);
        break;
      case 'onBluetoothPeerDisconnected':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        debugPrint('BLE onBluetoothPeerDisconnected: $data');
        onBluetoothPeerDisconnected?.call(data);
        break;
    }
  }

  /// Requests required Bluetooth runtime permissions on Android
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ].request();

      return statuses.values.every((status) =>
          status.isGranted || status.isLimited);
    } catch (_) {
      return false;
    }
  }

  /// Check whether broadcast was persisted as enabled
  Future<bool> getBroadcastEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final enabled = await _advertiserChannel.invokeMethod<bool>('getBroadcastEnabled');
      _isAdvertising = enabled ?? false;
      return _isAdvertising;
    } catch (_) {
      return false;
    }
  }

  /// Query local device Bluetooth name and MAC
  Future<Map<String, String>> getDeviceBluetoothInfo() async {
    if (!Platform.isAndroid) return {};
    try {
      final res = await _advertiserChannel.invokeMethod<Map>('getDeviceBluetoothInfo');
      if (res != null) {
        return Map<String, String>.from(res);
      }
    } catch (_) {}
    return {};
  }

  /// Sets the libp2p peer ID, handle and Wi-Fi multiaddrs this device presents
  /// in Bluetooth handshakes. Must be called before connecting, even when not
  /// advertising.
  Future<void> setLocalIdentity(String peerId, {String? name, List<String>? addrs}) async {
    if (!Platform.isAndroid) return;
    try {
      await _advertiserChannel.invokeMethod('setLocalIdentity', {
        'peerId': peerId,
        'name': name ?? '',
        'addrs': addrs ?? const <String>[],
      });
    } catch (e) {
      debugPrint('BLE setLocalIdentity error: $e');
    }
  }

  /// Starts broadcasting this device as a Chatter BLE node
  Future<bool> startAdvertising(String peerId, {String? address, String? name}) async {
    if (!Platform.isAndroid) return false;
    try {
      final granted = await requestPermissions();
      if (!granted) {
        debugPrint('BLE permissions not granted');
      }

      final success = await _advertiserChannel.invokeMethod<bool>(
        'startAdvertising',
        {
          'peerId': peerId,
          'address': address ?? '',
          'name': name ?? (peerId.length > 8 ? 'Chatter-${peerId.substring(0, 6)}' : 'Chatter'),
        },
      );
      _isAdvertising = success ?? false;
      return _isAdvertising;
    } catch (e) {
      debugPrint('BLE startAdvertising error: $e');
      _isAdvertising = false;
      return false;
    }
  }

  /// Stops broadcasting this device
  Future<void> stopAdvertising() async {
    if (!Platform.isAndroid) return;
    try {
      await _advertiserChannel.invokeMethod('stopAdvertising');
      _isAdvertising = false;
    } catch (_) {}
  }

  /// Connect to a remote device directly over Bluetooth: LE L2CAP when the
  /// peer advertised a [psm], otherwise RFCOMM (needs its classic MAC)
  Future<bool> connectBluetooth(String address, {String? peerId, int? psm}) async {
    if (!Platform.isAndroid) return false;
    try {
      await requestPermissions();
      final res = await _advertiserChannel.invokeMethod<bool>(
        'connectBluetooth',
        {
          'address': address,
          'peerId': peerId ?? '',
          'psm': psm ?? 0,
        },
      );
      return res ?? false;
    } catch (e) {
      debugPrint('connectBluetooth error: $e');
      rethrow;
    }
  }

  /// Send message over Bluetooth RFCOMM socket
  Future<bool> sendBluetoothMessage(String peerId, String content) async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _advertiserChannel.invokeMethod<bool>(
        'sendBluetoothMessage',
        {
          'peerId': peerId,
          'content': content,
        },
      );
      return res ?? false;
    } catch (e) {
      debugPrint('sendBluetoothMessage error: $e');
      rethrow;
    }
  }

  /// Query connected Bluetooth peers
  Future<List<Map<String, String>>> getConnectedBluetoothPeers() async {
    if (!Platform.isAndroid) return [];
    try {
      final res = await _advertiserChannel.invokeMethod<List>('getConnectedBluetoothPeers');
      if (res != null) {
        return res.map((item) => Map<String, String>.from(item as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Scans for nearby Chatter and BLE peers, giving priority to Chatter nodes
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isScanning) return;

    try {
      if (Platform.isAndroid) {
        await requestPermissions();
      }

      if (await FlutterBluePlus.isSupported == false) {
        debugPrint('Bluetooth is not supported on this device');
        return;
      }

      _isScanning = true;
      final chatterGuid = _chatterGuid;

      // Listen to scan results (replace any listener from a previous scan)
      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        final now = DateTime.now();

        for (final r in results) {
          final deviceId = r.device.remoteId.str;

          String? detectedMultiaddr;
          bool isChatter = false;
          int? psm;
          String? peerIdPrefix;

          // Check if device advertises the Chatter Service UUID
          if (r.advertisementData.serviceUuids.contains(chatterGuid)) {
            isChatter = true;
          }

          final advName = r.advertisementData.advName;
          final platName = r.device.platformName;

          if (advName.startsWith('Chatter') || platName.startsWith('Chatter')) {
            isChatter = true;
          }

          final serviceData = r.advertisementData.serviceData[chatterGuid];
          if (serviceData != null && serviceData.isNotEmpty) {
            isChatter = true;
            // v1 payload: [0x01][PSM hi][PSM lo][peer ID prefix]
            if (serviceData.length >= 3 && serviceData[0] == 0x01) {
              final p = (serviceData[1] << 8) | serviceData[2];
              if (p > 0) psm = p;
              peerIdPrefix = String.fromCharCodes(serviceData.sublist(3));
            } else {
              try {
                final payloadStr = String.fromCharCodes(serviceData);
                if (payloadStr.startsWith('/ip4/')) {
                  detectedMultiaddr = payloadStr;
                }
              } catch (_) {}
            }
          }

          // A Chatter peer advertises its handle; prefer it over the device name
          final handleData = r.advertisementData.serviceData[_handleGuid];
          final advHandle = handleData != null && handleData.isNotEmpty
              ? utf8.decode(handleData, allowMalformed: true)
              : '';

          final displayName = advHandle.isNotEmpty
              ? advHandle
              : advName.isNotEmpty
                  ? advName
                  : (platName.isNotEmpty
                      ? platName
                      : (isChatter
                          ? 'Chatter Peer (${deviceId.substring(0, min(5, deviceId.length))})'
                          : 'node-${deviceId.replaceAll(':', '').toLowerCase().substring(0, min(6, deviceId.length))}'));

          _seenNodes[deviceId] = (
            NearbyNode(
              id: deviceId,
              name: displayName,
              rssi: r.rssi,
              multiaddr: detectedMultiaddr,
              isChatterPeer: isChatter,
              psm: psm,
              peerIdPrefix: peerIdPrefix,
            ),
            now,
          );
        }

        _emitNearby();
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      _isScanning = false;
    } catch (e) {
      debugPrint('BLE startScan error: $e');
      _isScanning = false;
    }
  }

  void _emitNearby() {
    final cutoff = DateTime.now().subtract(_nearbyTtl);
    _seenNodes.removeWhere((_, entry) => entry.$2.isBefore(cutoff));
    final nodes = _seenNodes.values.map((entry) => entry.$1).toList()
      // Chatter peers first, then by signal strength (highest RSSI first)
      ..sort((a, b) {
        if (a.isChatterPeer && !b.isChatterPeer) return -1;
        if (!a.isChatterPeer && b.isChatterPeer) return 1;
        return b.rssi.compareTo(a.rssi);
      });
    _nearbyNodesController.add(nodes);
  }

  static int min(int a, int b) => a < b ? a : b;

  /// Stops scanning
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _isScanning = false;
  }

  void dispose() {
    _scanSubscription?.cancel();
    stopScan();
    stopAdvertising();
    _nearbyNodesController.close();
  }
}
