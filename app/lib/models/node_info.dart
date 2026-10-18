class NodeInfo {
  final String id;
  final List<String> addrs;

  const NodeInfo({required this.id, required this.addrs});

  factory NodeInfo.fromJson(Map<String, dynamic> json) => NodeInfo(
        id: json['id'] as String,
        addrs: List<String>.from(json['addrs'] as List? ?? []),
      );

  /// Returns routable LAN / Hotspot IPv4 addresses, strictly excluding loopback and IPv6.
  List<String> get routableAddrs {
    return addrs
        .where((a) =>
            !a.contains('/127.0.0.1/') &&
            !a.contains('/::1/') &&
            !a.contains('/ip6/'))
        .toList();
  }

  bool get hasRoutableAddrs => routableAddrs.isNotEmpty;

  /// Returns the routable multiaddress for QR sharing, or node ID if completely offline.
  String get qrPayload => routableAddrs.isNotEmpty ? routableAddrs.first : id;

  /// Truncated peer ID for display purposes.
  String get shortId =>
      id.length > 20 ? '${id.substring(0, 16)}…' : id;
}
