import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application_api.dart';
import '../models/node_info.dart';
import '../providers/theme_provider.dart';

class NodeSettingsScreen extends ConsumerStatefulWidget {
  const NodeSettingsScreen({super.key});

  @override
  ConsumerState<NodeSettingsScreen> createState() => _NodeSettingsScreenState();
}

class _NodeSettingsScreenState extends ConsumerState<NodeSettingsScreen> {
  final ApplicationAPI api = ApplicationAPI();
  bool _bgSync = true;
  bool _publishToDHT = false;
  bool _isBackendOnline = false;
  NodeInfo? _nodeInfo;

  @override
  void initState() {
    super.initState();
    _fetchNodeData();
  }

  Future<void> _fetchNodeData() async {
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    final peerIdDisplay = _nodeInfo != null
        ? 'PeerID ${_nodeInfo!.shortId}'
        : (_isBackendOnline ? 'PeerID loading...' : 'PeerID (Offline)');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Node Configuration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNodeData,
            tooltip: 'Refresh node info',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        children: [
          // Network Health Status
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Card(
              color: const Color(0xFF1E1A17),
              child: ListTile(
                leading: Icon(
                  Icons.wifi_tethering, 
                  color: _isBackendOnline ? const Color(0xFF4ADE80) : Colors.redAccent,
                ),
                title: Text(
                  _isBackendOnline ? 'Mesh Status: Active (Online)' : 'Mesh Status: Offline', 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _isBackendOnline ? 'Connected to local Go P2P daemon' : 'Connecting to local node...', 
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
          ),
          
          const Divider(color: Color(0xFF2A2420), height: 32),

          // --- APPEARANCE SECTION ---
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('APPEARANCE', style: TextStyle(color: Colors.grey, letterSpacing: 2, fontSize: 12)),
          ),
          SwitchListTile(
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: const Color(0xFF935F32)),
            title: const Text('Dark Theme'),
            subtitle: Text(isDark ? 'Terminal dark mode' : 'Sand light mode', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            value: isDark,
            activeThumbColor: const Color(0xFF4ADE80),
            onChanged: (val) {
              ref.read(themeProvider.notifier).toggleTheme(val);
            },
          ),

          const Divider(color: Color(0xFF2A2420), height: 32),

          // Node Identity
          ListTile(
            title: const Text('This node', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(peerIdDisplay, style: const TextStyle(color: Colors.grey, fontFamily: 'monospace')),
            trailing: _nodeInfo != null
                ? IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                    tooltip: 'Copy full PeerID',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _nodeInfo!.id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF935F32),
                          content: Text('Full Peer ID copied to clipboard!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  )
                : null,
          ),
          
          // Toggles
          SwitchListTile(
            title: const Text('Background sync'),
            subtitle: const Text('Keep gossiping while the app is closed', style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _bgSync,
            activeThumbColor: const Color(0xFF4ADE80),
            onChanged: (val) => setState(() => _bgSync = val),
          ),
          SwitchListTile(
            title: const Text('Publish to DHT'),
            subtitle: const Text('Let unknown peers discover your PeerID', style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _publishToDHT,
            activeThumbColor: const Color(0xFF4ADE80),
            onChanged: (val) => setState(() => _publishToDHT = val),
          ),

          const Divider(color: Color(0xFF2A2420), height: 32),

          // Delivery Legend
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('DELIVERY LEGEND', style: TextStyle(color: Colors.grey, letterSpacing: 2, fontSize: 12)),
          ),
          _buildLegendItem(Icons.access_time, 'Pending', 'Encrypted, queued locally', Colors.grey),
          _buildLegendItem(Icons.check, 'Delivered', 'Acknowledged by destination transport', Colors.grey),
          _buildLegendItem(Icons.done_all, 'Verified', 'Decrypted, signature validated', const Color(0xFF4ADE80)),
          _buildLegendItem(Icons.warning_amber_rounded, 'Orphaned', 'Message did not arrive', Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, String title, String subtitle, Color iconColor) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      dense: true,
    );
  }
}