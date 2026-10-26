class ChatMessage {
  final int id;
  final String from;
  final String content;
  final DateTime timestamp;

  /// Whether this message was sent by the local node.
  /// Messages fetched from GET /messages are always incoming.
  final bool isOutgoing;

  /// Mesh message ID; receipts refer to messages by it.
  final String? msgId;

  /// The sender's handle, signed by the sender.
  final String? handle;

  /// Neighbour the message arrived from; differs from [from] when relayed.
  final String? via;

  /// The channel it was posted to (an open room's name or a private room's
  /// tag), or null for a direct message.
  final String? room;

  /// A channel post caught up from a neighbour's history after joining (or
  /// meeting someone new), not received as it was sent; [timestamp] is then
  /// when its author wrote it.
  final bool isHistory;

  const ChatMessage({
    required this.id,
    required this.from,
    required this.content,
    required this.timestamp,
    this.isOutgoing = false,
    this.msgId,
    this.handle,
    this.via,
    this.room,
    this.isHistory = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        from: json['from'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        msgId: json['msg_id'] as String?,
        handle: json['handle'] as String?,
        via: json['via'] as String?,
        room: (json['room'] as String?)?.isEmpty == true ? null : json['room'] as String?,
        isHistory: json['history'] == true,
      );

  /// Whether another peer relayed this message to us.
  bool get isRelayed => via != null && via!.isNotEmpty && via != from;

  /// Optimistic local copy of a sent message (shown immediately on send).
  factory ChatMessage.outgoing({
    required String to,
    required String content,
  }) =>
      ChatMessage(
        id: -1,
        from: to,
        content: content,
        timestamp: DateTime.now(),
        isOutgoing: true,
      );
}

/// Confirmation from peer [from] that it received or read our messages [ids].
class Receipt {
  final int id;
  final String from;
  final List<String> ids;
  final String status; // "delivered" or "read"
  final String? via;

  const Receipt({
    required this.id,
    required this.from,
    required this.ids,
    required this.status,
    this.via,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
        id: json['id'] as int,
        from: json['from'] as String,
        ids: List<String>.from(json['ids'] as List? ?? const []),
        status: json['status'] as String,
        via: json['via'] as String?,
      );

  bool get isRelayed => via != null && via!.isNotEmpty && via != from;
}
