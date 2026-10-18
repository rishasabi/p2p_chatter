class ChatMessage {
  final int id;
  final String from;
  final String content;
  final DateTime timestamp;

  /// Whether this message was sent by the local node.
  /// Messages fetched from GET /messages are always incoming.
  final bool isOutgoing;

  const ChatMessage({
    required this.id,
    required this.from,
    required this.content,
    required this.timestamp,
    this.isOutgoing = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        from: json['from'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

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
