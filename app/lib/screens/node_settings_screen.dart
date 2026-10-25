import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application_api.dart';
import '../models/node_info.dart';
import '../providers/theme_provider.dart';
import '../services/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/peer_display.dart';

class NodeSettingsScreen extends ConsumerStatefulWidget {
  const NodeSettingsScreen({super.key});

  @override
  ConsumerState<NodeSettingsScreen> createState() => _NodeSettingsScreenState();
}

class _NodeSettingsScreenState extends ConsumerState<NodeSettingsScreen> {
  final ApplicationAPI api = ApplicationAPI();
  final SettingsStore _settings = SettingsStore();
  late bool _bgSync = _settings.getBool(SettingsStore.backgroundSync, fallback: true);
  late bool _publishToDHT = _settings.getBool(SettingsStore.publishToDht, fallback: false);
  late bool _readReceipts = _settings.getBool(SettingsStore.readReceipts, fallback: true);
  bool _isBackendOnline = false;
  // Until the first health check answers, don't claim the node is offline
  bool _isChecking = true;
  NodeInfo? _nodeInfo;

  @override
  void initState() {
    super.initState();
    _fetchNodeData();
  }

  Future<void> _fetchNodeData() async {
    if (!_isChecking) setState(() => _isChecking = true);
    try {
      final online = await api.checkHealth();
      NodeInfo? info;
      if (online) {
        info = await api.getNode();
      }
      if (mounted) {
        setState(() {
          _isBackendOnline = online;
          _nodeInfo = info;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.watch(themeProvider);
    final handle = api.myHandle;

    final peerIdDisplay = _nodeInfo != null
        ? compactPeerId(_nodeInfo!.id)
        : (_isChecking ? 'Loading peer ID…' : 'Peer ID unavailable while the node is offline');

    final (IconData statusIcon, Color statusColor, String statusTitle, String statusBody) = _isChecking
        ? (Icons.sync, cs.onSurfaceVariant, 'Checking your node…', 'Asking Chatter\'s local service for its status')
        : _isBackendOnline
            ? (Icons.wifi_tethering, ChatterColors.of(context).reach, 'Your node is running',
                'Chatter\'s local service is up and can reach peers')
            : (Icons.portable_wifi_off, cs.error, 'Your node isn\'t running',
                'The local service didn\'t answer. Try refreshing in a moment.');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isChecking ? null : _fetchNodeData,
            tooltip: 'Refresh node info',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Node health
          Semantics(
            liveRegion: true,
            child: ListTile(
              leading: Icon(statusIcon, color: statusColor),
              title: Text(statusTitle, style: theme.textTheme.titleMedium),
              subtitle: Text(statusBody),
            ),
          ),

          const _SectionHeader('Profile'),
          ListTile(
            // The handle is bound to this PeerID; peers see it instead of the ID
            leading: PeerAvatar(peerId: _nodeInfo?.id ?? '', name: handle ?? '?', size: 44),
            title: Text(handle != null ? '@$handle' : 'This phone', style: theme.textTheme.titleMedium),
            subtitle: Text(peerIdDisplay),
            trailing: _nodeInfo != null
                ? IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy full peer ID',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _nodeInfo!.id));
                      showNotice(context, 'Peer ID copied', tone: NoticeTone.success, duration: const Duration(seconds: 2));
                    },
                  )
                : null,
          ),

          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('System')),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (selection) => ref.read(themeProvider.notifier).setThemeMode(selection.first),
                  ),
                ),
              ],
            ),
          ),

          const _SectionHeader('Privacy and sync'),
          SwitchListTile(
            title: const Text('Send read receipts'),
            subtitle: const Text('Let people see when you\'ve read their messages'),
            value: _readReceipts,
            onChanged: (val) {
              setState(() => _readReceipts = val);
              _settings.set(SettingsStore.readReceipts, val);
            },
          ),
          SwitchListTile(
            title: const Text('Background sync'),
            subtitle: const Text('Keep passing messages along while the app is closed'),
            value: _bgSync,
            onChanged: (val) {
              setState(() => _bgSync = val);
              _settings.set(SettingsStore.backgroundSync, val);
            },
          ),
          SwitchListTile(
            title: const Text('Publish to DHT'),
            subtitle: const Text('Let people you haven\'t met find your peer ID'),
            value: _publishToDHT,
            onChanged: (val) {
              setState(() => _publishToDHT = val);
              _settings.set(SettingsStore.publishToDht, val);
            },
          ),

          const _SectionHeader('What the message icons mean'),
          _buildLegendItem(Icons.schedule, 'Sending', 'Leaving this phone'),
          _buildLegendItem(Icons.hourglass_empty, 'Waiting', 'No one in range yet. It goes out when someone is, and other phones pass it on'),
          _buildLegendItem(Icons.check, 'Sent', 'Handed to the mesh, directly or through other phones'),
          _buildLegendItem(Icons.done_all, 'Delivered', 'Their phone confirmed it arrived'),
          _buildLegendItem(Icons.visibility_outlined, 'Read', 'They opened the chat'),
          _buildLegendItem(Icons.error_outline, 'Not delivered', 'There was no Wi-Fi, Bluetooth or relay path at the time',
              color: cs.error),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, String title, String subtitle, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 4),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.primary)),
      ),
    );
  }
}
