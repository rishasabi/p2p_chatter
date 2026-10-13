// import 'package:flutter/material.dart';

// class NodeSettingsScreen extends StatelessWidget {
//   const NodeSettingsScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Network Health'),
//       ),
//       body: ListView(
//         padding: const EdgeInsets.all(16.0),
//         children: const [
//           Card(
//             color: Color(0xFF1E1A17),
//             child: ListTile(
//               leading: Icon(Icons.wifi_tethering, color: Color(0xFF4ADE80)),
//               title: Text('Mesh Status: Active', style: TextStyle(color: Colors.white)),
//               subtitle: Text('Listening for nearby relay nodes', style: TextStyle(color: Colors.grey)),
//             ),
//           ),
//           Card(
//             color: Color(0xFF1E1A17),
//             child: ListTile(
//               leading: Icon(Icons.alt_route, color: Color(0xFF935F32)),
//               title: Text('Known Multi-Hop Routes', style: TextStyle(color: Colors.white)),
//               subtitle: Text('4 nodes in DHT table', style: TextStyle(color: Colors.grey)),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';

class NodeSettingsScreen extends ConsumerStatefulWidget {
//class NodeSettingsScreen extends StatefulWidget {
  const NodeSettingsScreen({super.key});

  @override
  ConsumerState<NodeSettingsScreen> createState() => _NodeSettingsScreenState();
  //State<NodeSettingsScreen> createState() => _NodeSettingsScreenState();
}
class _NodeSettingsScreenState extends ConsumerState<NodeSettingsScreen>{
//class _NodeSettingsScreenState extends State<NodeSettingsScreen> {
  bool _bgSync = true;
  bool _actAsRelay = true;
  bool _publishToDHT = false;
  double _storageLimit = 60.0;

  @override
  Widget build(BuildContext context) {
    //added new for dark and light theme
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Node Configuration')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        children: [
          // Network Health Status
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: const [
                Card(
                  color: Color(0xFF1E1A17),
                  child: ListTile(
                    leading: Icon(Icons.wifi_tethering, color: Color(0xFF4ADE80)),
                    title: Text('Mesh Status: Active', style: TextStyle(color: Colors.white)),
                    subtitle: Text('Listening for nearby relay nodes', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ),
                ],
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
            activeColor: const Color(0xFF4ADE80),
            onChanged: (val) {
              ref.read(themeProvider.notifier).toggleTheme(val);
            },
          ),

          const Divider(color: Color(0xFF2A2420), height: 32),
          // Node Identity
          const ListTile(
            title: Text('This node', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('PeerID 7c4e·f10b·92da', style: TextStyle(color: Colors.grey)),
          ),
          
          // Toggles
          SwitchListTile(
            title: const Text('Background sync'),
            subtitle: const Text('Keep gossiping while the app is closed', style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _bgSync,
            activeColor: const Color(0xFF4ADE80),
            onChanged: (val) => setState(() => _bgSync = val),
          ),
         SwitchListTile(
            title: const Text('Publish to DHT'),
            subtitle: const Text('Let unknown peers discover your PeerID', style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _publishToDHT,
            activeColor: const Color(0xFF4ADE80),
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