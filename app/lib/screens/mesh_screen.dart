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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    peers = api.peers;
    _isLoading = peers.isEmpty;
    filteredPeers = List.from(peers);
    _loadPeers();
    _searchController.addListener(_filterPeers);
    api.onPeerUpdate(_handlePeerUpdate);
  }

  // Status changes are pushed as they happen (Wi-Fi or Bluetooth link up/down)
  void _handlePeerUpdate(Map<String, dynamic> update) {
    if (!mounted) return;
    peers = api.peers;
    _filterPeers();
  }

  Future<void> _loadPeers() async {
    try {
      final loadedPeers = await api.getPeers();
      if (mounted) {
        setState(() {
          peers = loadedPeers;
          _isLoading = false;
        });
        _filterPeers();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterPeers() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        filteredPeers = List.from(peers);
      } else {
        filteredPeers = peers.where((peer) {
          final name = peer['name'].toString().toLowerCase();
          final id = peer['id'].toString().toLowerCase();
          return name.contains(query) || id.contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    api.removeOnPeerUpdate(_handlePeerUpdate);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatter', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: 'Refresh peers',
            onPressed: () {
              setState(() => _isLoading = true);
              _loadPeers();
            },
          ),
        ],
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
                // Theme surface: the same dark fill in dark mode, light in light mode
                fillColor: Theme.of(context).colorScheme.surface,
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
            child: RefreshIndicator(
              color: const Color(0xFF935F32),
              onRefresh: _loadPeers,
              child: _isLoading && peers.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF935F32)))
                  : peers.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.speaker_phone, size: 48, color: Colors.grey.shade600),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No peers connected yet',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Scan a peer\'s code in the Discover tab to connect to the mesh network.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                  ),
                                  const SizedBox(height: 20),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text('Check again'),
                                    onPressed: () {
                                      setState(() => _isLoading = true);
                                      _loadPeers();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF935F32),
                                      side: const BorderSide(color: Color(0xFF935F32)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredPeers.length,
                          itemBuilder: (context, index) {
                            final peer = filteredPeers[index];
                            final name = peer['name'] ?? 'Peer';
                            final initial = name.length >= 2 ? name.substring(0, 2) : name;
                            final isOnline = peer['online'] == true;
                            final unread = peer['unread'] as int? ?? 0;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF1E1A17),
                                child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 13)),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${peer['type'] ?? 'OFFLINE'} · ${(peer['id'] as String).length > 12 ? '${(peer['id'] as String).substring(0, 12)}…' : peer['id']}',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (unread > 0)
                                    Container(
                                      margin: const EdgeInsets.only(right: 10),
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF935F32),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$unread',
                                        semanticsLabel: '$unread unread',
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: isOnline ? const Color(0xFF4ADE80) : Colors.grey,
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(peerName: name, peerId: peer['id']),
                              )),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}