// import 'package:flutter/material.dart';
// import '../application_api.dart';
// import 'chat_screen.dart';

// class MeshScreen extends StatefulWidget {
//   const MeshScreen({super.key});

//   @override
//   State<MeshScreen> createState() => _MeshScreenState();
// }

// class _MeshScreenState extends State<MeshScreen> {
//   final ApplicationAPI api = ApplicationAPI();
//   List<Map<String, dynamic>> peers = [];

//   @override
//   void initState() {
//     super.initState();
//     _loadPeers();
//   }

//   void _loadPeers() async {
//     final loadedPeers = await api.getPeers();
//     setState(() => peers = loadedPeers);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Ember', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
//       ),
//       body: peers.isEmpty 
//         ? const Center(child: CircularProgressIndicator(color: Color(0xFF935F32)))
//         : ListView.builder(
//             padding: const EdgeInsets.all(16),
//             itemCount: peers.length,
//             itemBuilder: (context, index) {
//               final peer = peers[index];
//               return ListTile(
//                 leading: CircleAvatar(
//                   backgroundColor: const Color(0xFF1E1A17),
//                   child: Text(peer['name'].substring(0, 2), style: const TextStyle(color: Colors.white)),
//                 ),
//                 title: Text(peer['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
//                 subtitle: Text(peer['type'], style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
//                 trailing: Icon(
//                   Icons.circle, 
//                   size: 10, 
//                   color: peer['online'] ? const Color(0xFF4ADE80) : Colors.grey
//                 ),
//                 onTap: () => Navigator.push(context, MaterialPageRoute(
//                   builder: (_) => ChatScreen(peerName: peer['name'], peerId: peer['id'], isOnline: peer['online']),
//                 )),
//               );
//             },
//           ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import '../application_api.dart';
import 'chat_screen.dart';

class MeshScreen extends StatefulWidget {
  const MeshScreen({super.key});

  @override
  State<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  final ApplicationAPI api = ApplicationAPI();
  List<Map<String, dynamic>> peers = [];
  List<Map<String, dynamic>> filteredPeers = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPeers();
    _searchController.addListener(_filterPeers);
  }

  void _loadPeers() async {
    final loadedPeers = await api.getPeers();
    setState(() {
      peers = loadedPeers;
      filteredPeers = loadedPeers;
    });
  }

  void _filterPeers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredPeers = peers.where((peer) {
        return peer['name'].toString().toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatter', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search peers...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1A17),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          
          // Threads List
          Expanded(
            child: peers.isEmpty 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF935F32)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredPeers.length,
                  itemBuilder: (context, index) {
                    final peer = filteredPeers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF1E1A17),
                        child: Text(peer['name'].substring(0, 2), style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(peer['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(peer['type'], style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      trailing: Icon(
                        Icons.circle, 
                        size: 10, 
                        color: peer['online'] ? const Color(0xFF4ADE80) : Colors.grey
                      ),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(peerName: peer['name'], peerId: peer['id'], isOnline: peer['online']),
                      )),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}