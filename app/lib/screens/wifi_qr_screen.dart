import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../application_api.dart';
import '../models/node_info.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/peer_identity.dart';
import 'chat_screen.dart';
import 'qr_scanner_screen.dart';

/// The top-bar shortcut to [WifiQrScreen].
class WifiQrButton extends StatelessWidget {
  const WifiQrButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.qr_code_scanner),
      tooltip: 'Wi-Fi QR connection',
      onPressed: () {
        FocusScope.of(context).unfocus();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WifiQrScreen()));
      },
    );
  }
}

/// Connecting over Wi-Fi or a shared hotspot: your own code to show, and a
/// way to scan someone else's. The camera only runs in [QrScannerScreen].
class WifiQrScreen extends StatefulWidget {
  /// The code to show until the node answers (tests have no node).
  final String initialCode;

  const WifiQrScreen({super.key, this.initialCode = ''});

  @override
  State<WifiQrScreen> createState() => _WifiQrScreenState();
}

class _WifiQrScreenState extends State<WifiQrScreen> {
  final ApplicationAPI api = ApplicationAPI();
  final BleService _bleService = BleService();

  late String _code = widget.initialCode;
  NodeInfo? _nodeInfo;
  bool _isLoadingNode = true;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _fetchLiveNodeData();
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
          _code = jsonEncode(payload);
          _isLoadingNode = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingNode = false);
      }
    }
  }

  /// A text field of a Chatter code (e.g. 'name', the handle), or null.
  static String? _fieldInCode(String code, String field) {
    try {
      final decoded = jsonDecode(code);
      if (decoded is Map && decoded[field] is String) return decoded[field] as String;
    } catch (_) {}
    return null;
  }

  Future<void> _scan() async {
    final code = await QrScannerScreen.scan(context);
    if (code != null && mounted) await _connect(code);
  }

  /// Connects to the peer in a scanned code and, when the code says who
  /// they are, opens the conversation in place of this screen.
  Future<void> _connect(String code) async {
    final name = _fieldInCode(code, 'name');
    setState(() => _isConnecting = true);
    String? peerId;
    try {
      // ApplicationAPI handles JSON QR payloads (Bluetooth first, then all TCP addrs)
      peerId = await api.connectPeer(code);
      if (mounted && peerId == null) {
        showNotice(context, name != null ? 'Connected to $name' : 'Connected', tone: NoticeTone.success);
      }
    } catch (e) {
      if (mounted) {
        showNotice(context, 'Could not connect. $e', tone: NoticeTone.error, duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
    if (peerId != null && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(peerName: api.displayName(peerId!), peerId: peerId),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi QR')),
      // Scanning stays in view on every screen size, never below the fold
      bottomNavigationBar: _buildScanBar(theme),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // First thing on screen, at any text size: the bar holding
                      // the scan button has to stay small enough not to crowd it
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.qr_code_scanner, color: theme.colorScheme.onSurface),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Point your camera at their code to connect without typing IP addresses. '
                              'The scan button stays at the bottom.',
                              style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionHeading('My Wi-Fi code'),
                      const SizedBox(height: 12),
                      _buildMyCode(math.min(constraints.maxWidth - 96, 260.0).clamp(160.0, 260.0)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isConnecting)
            Semantics(
              liveRegion: true,
              label: 'Connecting',
              child: ColoredBox(
                color: theme.colorScheme.scrim.withValues(alpha: 0.6),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyCode(double qrSize) {
    if (_isLoadingNode && _code.isEmpty) {
      return const StateMessage(fill: false, leading: CircularProgressIndicator(), title: 'Preparing your code');
    }
    if (_code.isEmpty) {
      return StateMessage(
        fill: false,
        icon: Icons.qr_code,
        title: 'Your code isn\'t ready',
        body: 'The local node didn\'t answer, so there is no code to share yet.',
        action: FilledButton(onPressed: _fetchLiveNodeData, child: const Text('Try again')),
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final handle = api.myHandle;
    final myId = _nodeInfo?.id ?? api.myPeerId ?? _fieldInCode(_code, 'id');

    return Column(
      children: [
        // The code carries network addresses, not a Bluetooth pairing;
        // say so before anyone tries it with Wi-Fi off
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi, size: 18, color: cs.onSecondaryContainer),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Wi-Fi / hotspot connection code',
                    style: theme.textTheme.labelLarge!.copyWith(color: cs.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Always dark on white, whatever the theme: scanners need the contrast
        Semantics(
          image: true,
          label: 'Your Wi-Fi connection code',
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: QrImageView(
              data: _code,
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
        // In full, so someone verifying you can check every character
        if (myId != null) ...[
          const SizedBox(height: 4),
          SelectableText(
            myId,
            style: theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant, fontFamily: 'monospace'),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'This QR code shares your local network address for high-speed Wi-Fi or mobile hotspot '
          'connection. To connect without Wi-Fi, use the Bluetooth \'Nearby\' tab.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 20),
              label: const Text('Copy code'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _code));
                showNotice(context, 'Code copied', tone: NoticeTone.success, duration: const Duration(seconds: 2));
              },
            ),
            if (myId != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.fingerprint, size: 20),
                label: const Text('Copy my peer ID'),
                onPressed: () => copyPeerId(context, myId),
              ),
          ],
        ),
      ],
    );
  }

  /// The way to scan someone else's code, pinned under whatever scrolls.
  Widget _buildScanBar(ThemeData theme) {
    final cs = theme.colorScheme;
    final chatter = ChatterColors.of(context);
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: chatter.accent,
                        foregroundColor: chatter.onAccent,
                      ),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan a peer\'s QR code'),
                      onPressed: _isConnecting ? null : _scan,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String text;
  const _SectionHeading(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(text, style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.primary)),
    );
  }
}
