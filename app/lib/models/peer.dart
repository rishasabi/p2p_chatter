class Peer {
  final String id;

  /// The peer's chosen handle, once its node has shared it.
  final String? handle;

  const Peer({required this.id, this.handle});

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        id: json['id'] as String,
        handle: (json['handle'] as String?)?.trim().isNotEmpty == true
            ? (json['handle'] as String).trim()
            : null,
      );

  /// Truncated peer ID for display purposes.
  String get shortId =>
      id.length > 20 ? '${id.substring(0, 16)}…' : id;
}
