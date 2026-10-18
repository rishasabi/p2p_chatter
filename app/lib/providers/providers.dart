import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../models/node_info.dart';
import '../models/peer.dart';
import '../services/api_service.dart';

// ── Service ──────────────────────────────────────────────────────────────────

/// Singleton [ChatterApiService] for the whole app.
final apiServiceProvider = Provider<ChatterApiService>(
  (ref) => ChatterApiService(),
);

// ── Health ───────────────────────────────────────────────────────────────────

/// Whether the backend is currently reachable.
final healthProvider = FutureProvider<bool>((ref) {
  return ref.read(apiServiceProvider).checkHealth();
});

// ── Node Info ────────────────────────────────────────────────────────────────

/// This node's peer ID and multiaddrs. Fetched once on app start.
final nodeInfoProvider = FutureProvider<NodeInfo>((ref) {
  return ref.read(apiServiceProvider).getNode();
});

// ── Peers ────────────────────────────────────────────────────────────────────

/// List of currently connected peers. Call [PeersNotifier.refresh] to update.
final peersProvider =
    AsyncNotifierProvider<PeersNotifier, List<Peer>>(PeersNotifier.new);

class PeersNotifier extends AsyncNotifier<List<Peer>> {
  @override
  Future<List<Peer>> build() => _fetch();

  Future<List<Peer>> _fetch() =>
      ref.read(apiServiceProvider).getPeers();

  /// Re-fetches the peer list from the backend.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

// ── Messages ─────────────────────────────────────────────────────────────────

/// Accumulated received messages. Call [MessagesNotifier.poll] periodically.
final messagesProvider =
    AsyncNotifierProvider<MessagesNotifier, List<ChatMessage>>(
        MessagesNotifier.new);

class MessagesNotifier extends AsyncNotifier<List<ChatMessage>> {
  int _lastId = -1;

  @override
  Future<List<ChatMessage>> build() async => [];

  /// Fetches any messages received since the last poll and appends them.
  Future<void> poll() async {
    final api = ref.read(apiServiceProvider);
    try {
      final incoming = await api.getMessages(afterId: _lastId);
      if (incoming.isEmpty) return;

      // Update high-water mark
      final maxId = incoming.map((m) => m.id).reduce((a, b) => a > b ? a : b);
      _lastId = maxId;

      final current = state.valueOrNull ?? [];
      state = AsyncData([...current, ...incoming]);
    } catch (e) {
      // Swallow polling errors silently — don't wipe existing messages
    }
  }

  /// Appends an optimistic outgoing message for immediate UI feedback.
  void addOutgoing(ChatMessage msg) {
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, msg]);
  }
}
