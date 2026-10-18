import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

/// Shows live network health: backend status, node ID, and peer count.
class NetworkStatusScreen extends ConsumerWidget {
  const NetworkStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(healthProvider);
    final nodeAsync = ref.watch(nodeInfoProvider);
    final peersAsync = ref.watch(peersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Health'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh all',
            onPressed: () {
              ref.invalidate(healthProvider);
              ref.invalidate(nodeInfoProvider);
              ref.read(peersProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Backend health
          _StatusCard(
            icon: healthAsync.when(
              loading: () =>
                  const Icon(Icons.wifi, color: Colors.grey),
              error: (_, __) =>
                  const Icon(Icons.wifi_off, color: Colors.red),
              data: (ok) => Icon(
                ok ? Icons.wifi_tethering : Icons.wifi_off,
                color: ok ? Colors.green : Colors.red,
              ),
            ),
            title: 'Backend Status',
            subtitle: healthAsync.when(
              loading: () => 'Checking…',
              error: (_, __) => 'Unreachable',
              data: (ok) => ok ? 'Online' : 'Offline',
            ),
          ),
          const SizedBox(height: 8),

          // Node identity
          _StatusCard(
            icon: const Icon(Icons.fingerprint, color: Colors.deepPurple),
            title: 'Node ID',
            subtitle: nodeAsync.when(
              loading: () => 'Loading…',
              error: (_, __) => 'N/A',
              data: (info) => info.shortId,
            ),
            subtitleMono: true,
          ),
          const SizedBox(height: 8),

          // Connected peers
          _StatusCard(
            icon: const Icon(Icons.people_outline, color: Colors.blue),
            title: 'Direct Connected Peers',
            subtitle: peersAsync.when(
              loading: () => 'Loading…',
              error: (_, __) => 'Unknown',
              data: (peers) =>
                  '${peers.length} ${peers.length == 1 ? 'node' : 'nodes'}',
            ),
          ),
          const SizedBox(height: 8),

          // Listening addresses
          if (nodeAsync.hasValue &&
              nodeAsync.value!.addrs.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.alt_route,
                            color: Colors.orange),
                        const SizedBox(width: 16),
                        Text(
                          'Listening Addresses',
                          style:
                              Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...nodeAsync.value!.addrs.map(
                      (addr) => Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 2),
                        child: SelectableText(
                          addr,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final bool subtitleMono;

  const _StatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleMono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: icon,
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: subtitleMono
              ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
              : null,
        ),
      ),
    );
  }
}
