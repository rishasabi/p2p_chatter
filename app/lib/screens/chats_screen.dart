import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/peer.dart';
import '../providers/providers.dart';
import 'chat_detail_screen.dart';

/// Shows the list of currently connected peers.
/// Tap a peer to open a chat thread.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peersAsync = ref.watch(peersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Direct Messages'),
        centerTitle: true,
      ),
      body: peersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err.toString(),
          onRetry: () => ref.read(peersProvider.notifier).refresh(),
        ),
        data: (peers) => peers.isEmpty
            ? _EmptyState(
                onRefresh: () => ref.read(peersProvider.notifier).refresh(),
              )
            : _PeerList(peers: peers),
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'chats_refresh',
        tooltip: 'Refresh peers',
        onPressed: () => ref.read(peersProvider.notifier).refresh(),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _PeerList extends StatelessWidget {
  final List<Peer> peers;
  const _PeerList({required this.peers});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: peers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final peer = peers[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.secondaryContainer,
            child: const Icon(Icons.person_outline),
          ),
          title: Text(
            peer.shortId,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          subtitle: const Text('Tap to open chat'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(peer: peer),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.speaker_phone,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'No peers connected yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan a QR code from a nearby peer to join the mesh',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: onRefresh,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              'Could not load peers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
