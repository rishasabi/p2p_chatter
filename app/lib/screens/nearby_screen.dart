import 'dart:async';
import 'package:flutter/material.dart';
import '../application_api.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/peer_display.dart';
import '../widgets/peer_identity.dart';
import 'chat_screen.dart';
import 'wifi_qr_screen.dart';

/// Phones running Chatter within Bluetooth range: no network needed, so this
/// is a tab of its own rather than one step further in.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final ApplicationAPI api = ApplicationAPI();
  final BleService _bleService = BleService();

  bool _isConnecting = false;
  bool _isBleAdvertising = false;
  bool _isTogglingBle = false;
  List<NearbyNode> _nearbyNodes = [];
  StreamSubscription<List<NearbyNode>>? _bleSubscription;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _initBle();
  }

  // Links coming up or down change what the list shows
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
  void dispose() {
    api.removeOnPeerUpdate(_handlePeerUpdate);
    _bleSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
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

  Future<void> _openChat(String peerId) async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(peerName: api.displayName(peerId), peerId: peerId),
      ),
    );
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

  /// Whether [node] matches the search: its advertised name, or the peer ID
  /// it advertises (or, once we know it, the full ID behind it and the name
  /// we gave it).
  bool _matchesSearch(NearbyNode node, String query) {
    if (query.isEmpty) return true;
    final prefix = node.peerIdPrefix ?? '';
    final peerId = prefix.isEmpty ? null : api.peerIdForPrefix(prefix);
    return [node.name, prefix, ?peerId, if (peerId != null) api.displayName(peerId)]
        .any((s) => s.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final query = _searchController.text.trim();
    final matches = _nearbyNodes.where((n) => _matchesSearch(n, query.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby'),
        actions: const [WifiQrButton(), SizedBox(width: 4)],
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: SwitchListTile(
              secondary: Icon(_isBleAdvertising ? Icons.bluetooth : Icons.bluetooth_disabled),
              title: const Text('Visible to nearby phones'),
              subtitle: Text(_isBleAdvertising
                  ? 'Phones running Chatter can find you over Bluetooth'
                  : 'Turn on so phones running Chatter can find you'),
              value: _isBleAdvertising,
              onChanged: _isTogglingBle ? null : (_) => _toggleBleAdvertising(),
            ),
          ),
          // Stays in reach while scrolling through a crowded shelter's worth of phones
          PinnedHeaderSliver(
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search nearby phones by name or ID…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
                          ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        query.isNotEmpty && _nearbyNodes.isNotEmpty
                            ? '${matches.length} of ${_nearbyNodes.length} phones nearby'
                            : 'Phones nearby',
                        style: theme.textTheme.titleSmall!.copyWith(color: cs.primary),
                      ),
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
          ),
          if (_nearbyNodes.isEmpty)
            SliverToBoxAdapter(child: _buildSearching())
          else if (matches.isEmpty)
            SliverToBoxAdapter(
              child: StateMessage(
                fill: false,
                icon: Icons.search_off,
                title: 'No nearby phones match \'$query\'',
                body: 'Try a handle, or the first few characters of a peer ID.',
                action: OutlinedButton.icon(
                  icon: const Icon(Icons.close, size: 20),
                  label: const Text('Clear search'),
                  onPressed: _searchController.clear,
                ),
              ),
            )
          else
            SliverList.list(children: [for (final node in matches) _buildNodeTile(node)]),
          const SliverPadding(padding: EdgeInsets.only(bottom: 8)),
        ],
      ),
    );
  }

  Widget _buildSearching() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
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
  Widget _buildNodeTile(NearbyNode node) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final prefix = node.peerIdPrefix ?? '';
    final peerId = api.peerIdForPrefix(prefix);
    final linked = peerId != null && api.isBluetoothLinked(peerId);
    final idText = peerId != null ? compactPeerId(peerId) : '$prefix…';
    final signal = _signalOf(node);
    // A phone we don't know yet can still be claiming a known handle
    final name = peerId != null ? api.displayName(peerId) : node.name;
    final verified = peerId != null && api.isVerified(peerId);
    final conflict = peerId != null ? api.hasHandleConflict(peerId) : api.advertisedHandleConflicts(node.name, prefix);
    final chatter = ChatterColors.of(context);

    return ListTile(
      key: ValueKey(prefix),
      leading: PeerAvatar(peerId: peerId ?? prefix, name: name, online: linked, size: 44),
      title: Row(
        children: [
          Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium)),
          if (verified || conflict) ...[
            const SizedBox(width: 6),
            TrustMark(verified: verified, conflict: conflict, size: 16),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(idText, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (peerId != null)
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy peer ID',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => copyPeerId(context, peerId),
                ),
            ],
          ),
          if (conflict)
            Text(
              'Handle also claimed by another device',
              style: theme.textTheme.bodySmall!.copyWith(color: chatter.warning, fontWeight: FontWeight.w600),
            ),
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
