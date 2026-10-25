import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../application_api.dart';
import '../models/node_info.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/peer_display.dart';
import 'chat_screen.dart';

class DiscoverScreen extends StatefulWidget {
  final String myBootstrapData;
  const DiscoverScreen({super.key, required this.myBootstrapData});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with WidgetsBindingObserver {
  final ApplicationAPI api = ApplicationAPI();
  final BleService _bleService = BleService();

  late final MobileScannerController _scannerController;
  bool _hasCameraPermission = false;
  bool _cameraPermanentlyDenied = false;
  bool _isCheckingPermission = true;
  bool _torchEnabled = false;

  String _currentBootstrapData = '';
  NodeInfo? _nodeInfo;
  bool _isLoadingNode = true;
  bool _isConnecting = false;
  bool _isBleAdvertising = false;
  bool _isTogglingBle = false;
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
    WidgetsBinding.instance.addObserver(this);
    _checkCameraPermission();
    _fetchLiveNodeData();
    _initBle();
  }

  Future<void> _checkCameraPermission() async {
    // Once permanently denied, only the system settings can grant it; the
    // result is picked up when the user comes back (didChangeAppLifecycleState)
    if (_cameraPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    setState(() => _isCheckingPermission = true);
    PermissionStatus status;
    try {
      status = await Permission.camera.request();
    } catch (e) {
      // No permission service (e.g. desktop): show the ask-again state, not an endless spinner
      debugPrint('Camera permission request failed: $e');
      status = PermissionStatus.denied;
    }
    if (mounted) {
      setState(() {
        _hasCameraPermission = status.isGranted;
        _cameraPermanentlyDenied = status.isPermanentlyDenied;
        _isCheckingPermission = false;
      });
    }
  }

  // Links coming up or down change what the Nearby list shows
  void _handlePeerUpdate(Map<String, dynamic> _) {
    if (mounted) setState(() {});
  }

  void _initBle() async {
    api.onPeerUpdate(_handlePeerUpdate);
    _bleSubscription = _bleService.nearbyNodes.listen((nodes) {
      if (mounted) {
        setState(() => _nearbyNodes = nodes);
      }
    });

    // ApplicationAPI starts the broadcast at launch; just reflect its state
    final broadcastEnabled = await _bleService.getBroadcastEnabled();
    if (mounted) {
      setState(() => _isBleAdvertising = broadcastEnabled);
    }

    _bleService.startScan();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_cameraPermanentlyDenied) return;
    Permission.camera.status.then((status) {
      if (mounted && status.isGranted) {
        setState(() {
          _hasCameraPermission = true;
          _cameraPermanentlyDenied = false;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    api.removeOnPeerUpdate(_handlePeerUpdate);
    _bleSubscription?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveNodeData() async {
    if (!_isLoadingNode) setState(() => _isLoadingNode = true);
    try {
      final info = await api.getNode();
      final btInfo = await _bleService.getDeviceBluetoothInfo();

      // Unified offline QR connection payload (JSON). 'name' is our handle,
      // so whoever scans it knows who they're talking to straight away.
      final payload = {
        'id': info.id,
        'name': api.myHandle ?? (btInfo['name']?.isNotEmpty == true ? btInfo['name'] : 'Chatter Peer'),
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

  Future<void> _toggleBleAdvertising() async {
    setState(() => _isTogglingBle = true);
    try {
      if (_isBleAdvertising) {
        await api.setBroadcastEnabled(false);
        if (mounted) {
          setState(() => _isBleAdvertising = false);
          showNotice(context, 'You\'re hidden from nearby phones', duration: const Duration(seconds: 2));
        }
      } else {
        final started = await api.setBroadcastEnabled(true);

        if (mounted) {
          setState(() => _isBleAdvertising = started);
          if (started) {
            showNotice(context, 'Nearby phones running Chatter can now find you',
                tone: NoticeTone.success, duration: const Duration(seconds: 2));
          } else {
            showNotice(context, 'Could not start Bluetooth visibility. Check that Bluetooth is on.',
                tone: NoticeTone.error);
          }
        }
      }
    } finally {
      if (mounted) setState(() => _isTogglingBle = false);
    }
  }

  /// Opens the conversation with [peerId] on top of the Discover screen.
  Future<void> _openChat(String peerId) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(peerName: api.displayName(peerId), peerId: peerId),
      ),
    );
  }

  /// The handle inside a scanned Chatter code, for messages only.
  static String? _nameInCode(String code) {
    try {
      final decoded = jsonDecode(code);
      if (decoded is Map && decoded['name'] is String) return decoded['name'] as String;
    } catch (_) {}
    return null;
  }

  /// Connects to the peer in a scanned code. Returns its peer ID when the
  /// connection succeeded and the code names the peer, otherwise null.
  Future<String?> _connectToPeer(String address) async {
    final cleanAddr = address.trim();
    if (cleanAddr.isEmpty) return null;

    setState(() => _isConnecting = true);
    final name = _nameInCode(cleanAddr);

    showNotice(context, name != null ? 'Connecting to $name…' : 'Connecting…',
        duration: const Duration(seconds: 2));

    try {
      // ApplicationAPI handles JSON QR payloads (Bluetooth first, then all TCP addrs)
      final peerId = await api.connectPeer(cleanAddr);

      if (mounted && peerId == null) {
        showNotice(context, name != null ? 'Connected to $name' : 'Connected', tone: NoticeTone.success);
      }
      return peerId;
    } catch (e) {
      if (mounted) {
        showNotice(context, 'Could not connect. $e', tone: NoticeTone.error, duration: const Duration(seconds: 4));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _handleBlePair(NearbyNode node) async {
    setState(() => _isConnecting = true);

    showNotice(context, 'Connecting to ${node.name} over Bluetooth…');

    String? peerId;
    try {
      await api.connectBluetooth(node.id, peerId: node.peerIdPrefix, psm: node.psm);
      // The handshake tells us exactly who answered
      final prefix = node.peerIdPrefix;
      peerId = prefix != null ? await api.waitForBluetoothPeer(prefix) : null;
      if (mounted && peerId == null) {
        showNotice(context, 'Connected to ${node.name} over Bluetooth', tone: NoticeTone.success);
      }
    } catch (e) {
      if (mounted) {
        showNotice(context, 'Could not connect to ${node.name} over Bluetooth. $e',
            tone: NoticeTone.error, duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
    if (peerId != null) await _openChat(peerId);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discover'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.qr_code), text: 'My code'),
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan'),
              Tab(icon: Icon(Icons.bluetooth_searching), text: 'Nearby'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Show Own QR Code (Always available offline, with Bluetooth identity)
            _buildMyCodeTab(),

            // Tab 2: Scan Peer's QR Code
            _buildScannerTab(),

            // Tab 3: Nearby BLE Nodes for Pairing
            _buildNearbyBleTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildMyCodeTab() {
    if (_isLoadingNode) {
      return const StateMessage(
        leading: CircularProgressIndicator(),
        title: 'Preparing your code',
      );
    }
    if (_currentBootstrapData.isEmpty) {
      return StateMessage(
        icon: Icons.qr_code,
        title: 'Your code isn\'t ready',
        body: 'The local node didn\'t answer, so there is no code to share yet.',
        action: FilledButton(onPressed: _fetchLiveNodeData, child: const Text('Try again')),
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final handle = api.myHandle;

    return LayoutBuilder(
      builder: (context, constraints) {
        final qrSize = math.min(constraints.maxWidth - 96, 260.0).clamp(160.0, 260.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  // Always dark on white, whatever the theme: scanners need the contrast
                  Semantics(
                    image: true,
                    label: 'Your connection code',
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: QrImageView(
                        data: _currentBootstrapData,
                        version: QrVersions.auto,
                        size: qrSize,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF12161C)),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF12161C),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (handle != null) Text('@$handle', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                  if (_nodeInfo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      compactPeerId(_nodeInfo!.id),
                      style: theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Ask the other person to scan this from their Discover tab. You\'ll connect over Bluetooth or the local network.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 20),
                    label: const Text('Copy code as text'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _currentBootstrapData));
                      showNotice(context, 'Code copied', tone: NoticeTone.success, duration: const Duration(seconds: 2));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScannerTab() {
    if (_isCheckingPermission) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasCameraPermission) {
      return StateMessage(
        icon: Icons.no_photography_outlined,
        title: 'Allow camera access to scan',
        body: _cameraPermanentlyDenied
            ? 'Camera access is turned off for Chatter. Turn it on in system settings, then come back.'
            : 'Chatter only uses the camera to read other people\'s connection codes.',
        action: FilledButton(
          onPressed: _checkCameraPermission,
          child: Text(_cameraPermanentlyDenied ? 'Open settings' : 'Allow camera'),
        ),
      );
    }

    // The navigation keeps this screen alive behind other tabs with tickers
    // off; take the scanner out then, which stops the camera
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;

    // The camera feed is always dark, so the overlay uses fixed light-on-dark
    // colours rather than the theme's
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = math.min(constraints.biggest.shortestSide * 0.68, 280.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: (capture) async {
                if (_isConnecting) return;
                final rawValue = capture.barcodes
                    .map((b) => b.rawValue?.trim())
                    .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
                if (rawValue == null) return;

                // Immediately set flag synchronously to prevent repeat frames from firing duplicate dials
                setState(() => _isConnecting = true);
                await _scannerController.stop();
                final peerId = await _connectToPeer(rawValue);
                if (peerId != null) {
                  // Straight into the conversation; the camera stays off meanwhile
                  await _openChat(peerId);
                } else {
                  await Future.delayed(const Duration(seconds: 2));
                }
                if (mounted && TickerMode.valuesOf(context).enabled) {
                  await _scannerController.start();
                }
              },
            ),

            // Viewfinder
            IgnorePointer(
              child: Center(
                child: Container(
                  width: box,
                  height: box,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.ember, width: 3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),

            // Torch
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                tooltip: _torchEnabled ? 'Turn flashlight off' : 'Turn flashlight on',
                isSelected: _torchEnabled,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.square(48),
                ),
                icon: const Icon(Icons.flash_off),
                selectedIcon: const Icon(Icons.flash_on, color: AppTheme.ember),
                onPressed: () {
                  _scannerController.toggleTorch();
                  setState(() => _torchEnabled = !_torchEnabled);
                },
              ),
            ),

            // Hint
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Point at someone\'s Chatter code to connect',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium!.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),

            if (_isConnecting)
              Semantics(
                liveRegion: true,
                label: 'Connecting',
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.85),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppTheme.ember),
                        const SizedBox(height: 16),
                        Text('Connecting…', style: textTheme.bodyLarge!.copyWith(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildNearbyBleTab() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SwitchListTile(
          secondary: Icon(_isBleAdvertising ? Icons.bluetooth : Icons.bluetooth_disabled),
          title: const Text('Visible to nearby phones'),
          subtitle: Text(_isBleAdvertising
              ? 'Phones running Chatter can find you over Bluetooth'
              : 'Turn on so phones running Chatter can find you'),
          value: _isBleAdvertising,
          onChanged: _isTogglingBle ? null : (_) => _toggleBleAdvertising(),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Phones nearby', style: theme.textTheme.titleSmall!.copyWith(color: cs.primary)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _bleService.startScan(),
                tooltip: 'Scan again',
              ),
            ],
          ),
        ),

        if (_nearbyNodes.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Looking for phones running Chatter', style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 4),
                      Text(
                        'They show up here when Chatter is open on them and they\'re visible to nearby phones.',
                        style: theme.textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          ..._nearbyNodes.map((node) => _buildLiveNodeTile(node)),
      ],
    );
  }

  static ({IconData icon, String word}) _signalOf(NearbyNode node) => switch (node.signalStrength) {
        'EXCELLENT' => (icon: Icons.signal_cellular_alt, word: 'Excellent signal'),
        'GOOD' => (icon: Icons.signal_cellular_alt, word: 'Good signal'),
        'FAIR' => (icon: Icons.signal_cellular_alt_2_bar, word: 'Fair signal'),
        _ => (icon: Icons.signal_cellular_alt_1_bar, word: 'Weak signal'),
      };

  // Identified by peer ID, never by Bluetooth address: the address is a
  // rotating private one that means nothing to the user
  Widget _buildLiveNodeTile(NearbyNode node) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final prefix = node.peerIdPrefix ?? '';
    final peerId = api.peerIdForPrefix(prefix);
    final linked = peerId != null && api.isBluetoothLinked(peerId);
    final idText = peerId != null ? compactPeerId(peerId) : '$prefix…';
    final signal = _signalOf(node);

    return ListTile(
      key: ValueKey(prefix),
      leading: PeerAvatar(peerId: peerId ?? prefix, name: node.name, online: linked, size: 44),
      title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(idText, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(signal.icon, size: 16, color: cs.onSurfaceVariant),
              Text(linked ? '${signal.word}, linked' : signal.word, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
      trailing: linked
          ? FilledButton(onPressed: () => _openChat(peerId), child: const Text('Chat'))
          : OutlinedButton(
              onPressed: _isConnecting ? null : () => _handleBlePair(node),
              child: const Text('Connect'),
            ),
    );
  }
}
