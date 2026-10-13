import 'package:flutter/material.dart';
import '../application_api.dart';

class ChatScreen extends StatefulWidget {
  final String peerName;
  final String peerId;
  final bool isOnline;

  const ChatScreen({super.key, required this.peerName, required this.peerId, required this.isOnline});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ApplicationAPI api = ApplicationAPI();
  late bool _isOnline;

  @override
  void initState() {
    super.initState();
    _isOnline = widget.isOnline;
    
    api.onPeerUpdate((update) {
      if (update['id'] == widget.peerId) {
        setState(() => _isOnline = update['online']);
      }
    });

    api.onMessage((msg) {
      // Handle incoming decrypted payload here
    });
  }

  void _handleSend() {
    if (_msgController.text.isNotEmpty) {
      api.sendMessage(_msgController.text, widget.peerId);
      _msgController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerName, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, size: 8, color: _isOnline ? const Color(0xFF4ADE80) : Colors.grey),
                const SizedBox(width: 6),
                Text(
                  _isOnline ? 'Online' : 'Offline', 
                  style: TextStyle(fontSize: 12, color: _isOnline ? const Color(0xFF4ADE80) : Colors.grey)
                ),
              ],
            )
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                 Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF935F32).withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('connection established over BLE', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF14110F),
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFF1E1A17), borderRadius: BorderRadius.circular(30)),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.attach_file, color: Colors.grey), onPressed: () {}),
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        decoration: const InputDecoration(
                          hintText: 'message the mesh', 
                          hintStyle: TextStyle(color: Colors.grey), 
                          border: InputBorder.none
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Color(0xFF935F32), shape: BoxShape.circle),
                      child: IconButton(icon: const Icon(Icons.arrow_upward, color: Colors.black, size: 20), onPressed: _handleSend),
                    )
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}