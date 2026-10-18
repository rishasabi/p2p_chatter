class Peer {
  final String id;

  const Peer({required this.id});

  factory Peer.fromJson(Map<String, dynamic> json) =>
      Peer(id: json['id'] as String);

  /// Truncated peer ID for display purposes.
  String get shortId =>
      id.length > 20 ? '${id.substring(0, 16)}…' : id;
}
