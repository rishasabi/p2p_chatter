import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../application_api.dart';
import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String peerName;
  final String peerId;

  const ChatScreen({
    super.key,
    required this.peerName,
    required this.peerId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApplicationAPI api = ApplicationAPI();
  // Live status: name (handle) and which transports reach the peer right now
  late Map<String, dynamic> _status;
  final List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _status = api.peerStatus(widget.peerId);
    _messages.addAll(api.historyFor(widget.peerId));

    api.onPeerUpdate(_handlePeerUpdate);
    api.onMessage(_handleIncomingMessage);
  }

  void _handlePeerUpdate(Map<String, dynamic> update) {
    if (mounted && update['id'] == widget.peerId) {
      setState(() => _status = update);
    }
  }

  bool get _isOnline => _status['online'] == true;

  String get _peerName => _status['name'] as String? ?? widget.peerName;

  String get _statusText {
    if (!_isOnline) return 'Offline';
    final wifi = _status['wifi'] == true;
    final bt = _status['bt'] == true;
    return 'Online · ${wifi && bt ? 'Wi-Fi + Bluetooth' : wifi ? 'Wi-Fi' : 'Bluetooth'}';
  }

  void _handleIncomingMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    if (msg['from'] == widget.peerId) {
      setState(() {
        _messages.add({
          'content': msg['content'] ?? '',
          'isOutgoing': false,
          'timestamp': DateTime.tryParse(msg['timestamp'] ?? '') ?? DateTime.now(),
        });
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    _msgController.clear();
    final entry = <String, dynamic>{
      'content': text,
      'isOutgoing': true,
      'timestamp': DateTime.now(),
    };
    setState(() {
      _isSending = true;
      _messages.add(entry);
    });
    _scrollToBottom();

    try {
      await api.sendMessage(text, widget.peerId);
    } catch (e) {
      if (mounted) {
        setState(() => entry['failed'] = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text('Failed to deliver: ${e is ApiException ? e.message : e}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  void dispose() {
    api.removeOnPeerUpdate(_handlePeerUpdate);
    api.removeOnMessage(_handleIncomingMessage);
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_peerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.circle, size: 8, color: _isOnline ? const Color(0xFF4ADE80) : Colors.grey),
                const SizedBox(width: 6),
                Text(
                  _statusText,
                  style: TextStyle(fontSize: 11, color: _isOnline ? const Color(0xFF4ADE80) : Colors.grey)
                ),
              ],
            )
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFF935F32).withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline, size: 14, color: Color(0xFF935F32)),
                                const SizedBox(width: 8),
                                Text(
                                  'P2P stream open with $_peerName',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('Send a message to start communicating.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      final bool isOut = item['isOutgoing'] == true;
                      final bool failed = item['failed'] == true;
                      final DateTime time = item['timestamp'] as DateTime;
                      // The Go node stamps messages in UTC; show local time
                      final timeStr = DateFormat('HH:mm').format(time.toLocal());

                      return Align(
                        alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isOut ? const Color(0xFF935F32) : const Color(0xFF1E1A17),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: isOut ? const Radius.circular(16) : Radius.zero,
                              bottomRight: isOut ? Radius.zero : const Radius.circular(16),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['content'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (failed) ...[
                                    const Icon(Icons.error_outline, size: 12, color: Color(0xFFFECACA)),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    failed ? 'not delivered · $timeStr' : timeStr,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: failed
                                          ? const Color(0xFFFECACA)
                                          : (isOut ? Colors.white70 : Colors.grey.shade500),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF14110F),
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1A17),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'message the mesh', 
                          hintStyle: TextStyle(color: Colors.grey), 
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _handleSend(),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF935F32),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_upward, color: Colors.black, size: 20),
                        onPressed: _handleSend,
                      ),
                    ),
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