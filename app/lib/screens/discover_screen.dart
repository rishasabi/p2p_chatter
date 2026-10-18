import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../application_api.dart';
import '../models/node_info.dart';
import '../services/ble_service.dart';

class DiscoverScreen extends StatefulWidget {
  final String myBootstrapData;
  const DiscoverScreen({super.key, required this.myBootstrapData});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final ApplicationAPI api = ApplicationAPI();
  final BleService _bleService = BleService();

  late final MobileScannerController _scannerController;
  bool _hasCameraPermission = false;
  bool _isCheckingPermission = true;
  bool _torchEnabled = false;

  String _currentBootstrapData = '';
  NodeInfo? _nodeInfo;
  bool _isLoadingNode = true;
  bool _isConnecting = false;
  bool _isBleAdvertising = false;
  List<NearbyNode> _nearbyNodes = [];
  StreamSubscription<List<NearbyNode>>? _bleSubscription;

  @override
  void initState() {
    super.initState();
    _currentBootstrapData = widget.myBootstrapData;
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _checkCameraPermission();
    _fetchLiveNodeData();
    _initBle();
  }

  Future<void> _checkCameraPermission() async {
    setState(() => _isCheckingPermission = true);
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _hasCameraPermission = status.isGranted;
        _isCheckingPermission = false;
      });
    }
  }

  void _initBle() async {
    _bleSubscription = _bleService.nearbyNodes.listen((nodes) {
      if (mounted) {
        setState(() => _nearbyNodes = nodes);
      }
    });

    // Check persistent broadcast preference and auto-start if previously enabled
    final broadcastPersisted = await _bleService.getBroadcastEnabled();
    if (mounted) {
      setState(() => _isBleAdvertising = broadcastPersisted);
    }
    if (broadcastPersisted) {
      _startAdvertisingInternal();
    }

    _bleService.startScan();
  }

  @override
  void dispose() {
    _bleSubscription?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveNodeData() async {
    try {
      final info = await api.getNode();
      final btInfo = await _bleService.getDeviceBluetoothInfo();

      // Unified offline QR connection payload (JSON)
      final payload = {
        'id': info.id,
        'name': btInfo['name']?.isNotEmpty == true ? btInfo['name'] : 'Chatter Peer',
        if (btInfo['address']?.isNotEmpty == true && btInfo['address'] != '02:00:00:00:00:00')
          'bt': btInfo['address'],
        if (info.hasRoutableAddrs) 'addrs': info.routableAddrs,
      };

      if (mounted) {
        setState(() {
          _nodeInfo = info;
          _currentBootstrapData = jsonEncode(payload);
          _isLoadingNode = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingNode = false);
      }
    }
  }

  Future<void> _startAdvertisingInternal() async {
    final peerId = _nodeInfo?.id ?? 'chatter-node';
    final btInfo = await _bleService.getDeviceBluetoothInfo();
    final name = btInfo['name']?.isNotEmpty == true
        ? btInfo['name']
        : (peerId.length > 8 ? 'Chatter-${peerId.substring(0, 6)}' : 'Chatter');

    await _bleService.startAdvertising(
      peerId,
      address: _currentBootstrapData,
      name: name,
    );
  }

  Future<void> _toggleBleAdvertising() async {
    if (_isBleAdvertising) {
      await _bleService.stopAdvertising();
      if (mounted) {
        setState(() => _isBleAdvertising = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF1E1A17),
            content: Text('BLE Broadcast stopped'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      final peerId = _nodeInfo?.id ?? 'chatter-node';
      final btInfo = await _bleService.getDeviceBluetoothInfo();
      final name = btInfo['name']?.isNotEmpty == true
          ? btInfo['name']
          : (peerId.length > 8 ? 'Chatter-${peerId.substring(0, 6)}' : 'Chatter');

      final started = await _bleService.startAdvertising(
        peerId,
        address: _currentBootstrapData,
        name: name,
      );

      if (mounted) {
        setState(() => _isBleAdvertising = started);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: started ? const Color(0xFF16A34A) : Colors.red.shade900,
            content: Text(started
                ? 'Broadcasting node over Bluetooth (persisted in storage)'
                : 'Failed to start BLE advertising (check Bluetooth settings)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _connectToPeer(String address) async {
    final cleanAddr = address.trim();
    if (cleanAddr.isEmpty) return;

    setState(() => _isConnecting = true);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E1A17),
        content: Text('Connecting to peer:\n$cleanAddr', style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      if (cleanAddr.startsWith('{')) {
        try {
          final data = jsonDecode(cleanAddr) as Map<String, dynamic>;
          final btMac = data['bt'] as String? ?? '';
          final peerId = data['id'] as String? ?? '';
          final addrs = data['addrs'] as List? ?? [];

          if (btMac.isNotEmpty && btMac != '02:00:00:00:00:00') {
            await _bleService.connectBluetooth(btMac, peerId: peerId);
          } else if (addrs.isNotEmpty) {
            await api.connectPeer(addrs.first.toString());
          } else if (peerId.isNotEmpty) {
            await api.connectPeer(peerId);
          }
        } catch (_) {
          await api.connectPeer(cleanAddr);
        }
      } else {
        await api.connectPeer(cleanAddr);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF16A34A),
            content: Text('Successfully connected to peer!'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text('Connection note: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _handleBlePair(NearbyNode node) async {
    setState(() => _isConnecting = true);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E1A17),
        content: Text('Connecting to ${node.name} via Bluetooth RFCOMM...'),
        duration: const Duration(seconds: 3),
      ),
    );

    try {
      await _bleService.connectBluetooth(node.id, peerId: node.name);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            content: Text('Connected to ${node.name} via Bluetooth!'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text('Bluetooth connection note: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discover'),
          bottom: const TabBar(
            indicatorColor: Color(0xFF935F32),
            labelColor: Color(0xFF935F32),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.qr_code), text: 'My Code'),
              Tab(icon: Icon(Icons.camera_alt), text: 'Scan'),
              Tab(icon: Icon(Icons.bluetooth_searching), text: 'Nearby'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Show Own QR Code (Always available offline, with Bluetooth identity)
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isLoadingNode)
                      const Column(
                        children: [
                          CircularProgressIndicator(color: Color(0xFF935F32)),
                          SizedBox(height: 16),
                          Text('Preparing node identity...',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: QrImageView(
                          data: _currentBootstrapData.isNotEmpty
                              ? _currentBootstrapData
                              : (_nodeInfo?.id ?? 'chatter-node'),
                          version: QrVersions.auto,
                          size: 220.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Have your peer scan this QR code to connect directly via Bluetooth or local network.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _currentBootstrapData));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF935F32),
                              content: Text('Address copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1A17),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2A2420)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.copy, size: 14, color: Color(0xFF935F32)),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _currentBootstrapData.length > 35
                                      ? '${_currentBootstrapData.substring(0, 32)}…'
                                      : _currentBootstrapData,
                                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Tab 2: Scan Peer's QR Code
            _buildScannerTab(),

            // Tab 3: Nearby BLE Nodes for Pairing
            _buildNearbyBleTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerTab() {
    if (_isCheckingPermission) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF935F32)),
      );
    }

    if (!_hasCameraPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 56, color: Color(0xFF935F32)),
              const SizedBox(height: 16),
              const Text(
                'Camera Access Required',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'To scan peer QR codes, please grant camera permissions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _checkCameraPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF935F32),
                  foregroundColor: Colors.white,
                ),
                child: const Text('ALLOW CAMERA'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: (capture) async {
            if (_isConnecting) return;
            for (final barcode in capture.barcodes) {
              final rawValue = barcode.rawValue?.trim();
              if (rawValue != null && rawValue.isNotEmpty) {
                // Immediately set flag synchronously to prevent repeat frames from firing duplicate dials
                setState(() => _isConnecting = true);
                try {
                  await _scannerController.stop();
                  await _connectToPeer(rawValue);
                } finally {
                  if (mounted) {
                    await Future.delayed(const Duration(seconds: 2));
                    if (mounted) {
                      await _scannerController.start();
                    }
                  }
                }
                break;
              }
            }
          },
        ),

        // Viewfinder overlay
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF4ADE80), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Torch button
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              icon: Icon(
                _torchEnabled ? Icons.flash_on : Icons.flash_off,
                color: _torchEnabled ? const Color(0xFF4ADE80) : Colors.white,
              ),
              onPressed: () {
                _scannerController.toggleTorch();
                setState(() => _torchEnabled = !_torchEnabled);
              },
            ),
          ),
        ),

        // Hint bar
        const Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Center(
            child: Text(
              'Align QR code inside the box to connect',
              style: TextStyle(color: Colors.white70, fontSize: 12, backgroundColor: Colors.black54),
            ),
          ),
        ),

        if (_isConnecting)
          Container(
            color: Colors.black87,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF935F32)),
                  SizedBox(height: 16),
                  Text('Connecting to peer...', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNearbyBleTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // BLE Broadcast Controls Card
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A17),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2420)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.bluetooth,
                color: _isBleAdvertising ? const Color(0xFF4ADE80) : const Color(0xFF935F32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isBleAdvertising ? 'BLE BROADCAST ACTIVE' : 'BLE OFFLINE BEACON',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      _isBleAdvertising
                          ? 'Broadcasting Chatter presence (persisted in storage)'
                          : 'Tap BROADCAST so other phones running Chatter discover you',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _toggleBleAdvertising,
                style: TextButton.styleFrom(
                  backgroundColor: _isBleAdvertising ? const Color(0xFF16A34A) : const Color(0xFF2A2420),
                  foregroundColor: Colors.white,
                ),
                child: Text(_isBleAdvertising ? 'STOP' : 'BROADCAST'),
              ),
            ],
          ),
        ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('NEARBY BLUETOOTH NODES', style: TextStyle(color: Colors.grey, letterSpacing: 2, fontSize: 12)),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF935F32)),
              onPressed: () => _bleService.startScan(),
              tooltip: 'Rescan BLE',
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_nearbyNodes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0),
            child: Center(
              child: Column(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF935F32)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Scanning for nearby Chatter devices...',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          ..._nearbyNodes.map((node) => _buildLiveNodeTile(node)),
      ],
    );
  }

  Widget _buildLiveNodeTile(NearbyNode node) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: node.isChatterPeer ? const Color(0xFF1A2E1D) : const Color(0xFF1E1A17),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: node.isChatterPeer ? const Color(0xFF16A34A) : const Color(0xFF2A2420),
          width: node.isChatterPeer ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          node.isChatterPeer ? Icons.bluetooth_connected : Icons.bluetooth,
          color: node.isChatterPeer ? const Color(0xFF4ADE80) : Colors.grey,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: node.isChatterPeer ? Colors.white : Colors.grey.shade300,
                ),
              ),
            ),
            if (node.isChatterPeer)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF4ADE80)),
                ),
                child: const Text('CHATTER APP', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        subtitle: Text(
          '${node.id} · ${node.rssi} dBm · ${node.signalStrength}',
          style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
        ),
        trailing: ElevatedButton(
          onPressed: () => _handleBlePair(node),
          style: ElevatedButton.styleFrom(
            backgroundColor: node.isChatterPeer ? const Color(0xFF16A34A) : const Color(0xFF2A2420),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          child: Text(node.isChatterPeer ? 'CONNECT' : 'PAIR'),
        ),
      ),
    );
  }
}