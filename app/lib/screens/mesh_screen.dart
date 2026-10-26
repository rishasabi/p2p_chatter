import 'package:flutter/material.dart';
import '../application_api.dart';
import '../services/draft_store.dart';
import '../widgets/brand_mark.dart';
import '../widgets/feedback.dart';
import '../widgets/mesh_map.dart';
import '../widgets/message_text.dart';
import '../widgets/peer_display.dart';
import '../widgets/peer_identity.dart';
import '../widgets/time_format.dart';
import 'chat_screen.dart';
import 'wifi_qr_screen.dart';

class MeshScreen extends StatefulWidget {
  const MeshScreen({super.key});

  @override
  State<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  final ApplicationAPI api = ApplicationAPI();
  final DraftStore _drafts = DraftStore();
  List<Map<String, dynamic>> peers = [];
  List<Map<String, dynamic>> filteredPeers = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    peers = api.peers;
    _isLoading = peers.isEmpty;
    filteredPeers = List.from(peers);
    _loadPeers();
    _searchController.addListener(_filterPeers);
    api.onPeerUpdate(_handlePeerUpdate);
    api.onHistoryChanged(_handleHistoryChanged);
    _drafts.addListener(_handleDraftsChanged);
  }

  // "Draft:" appears and goes as text is typed or sent
  void _handleDraftsChanged() {
    if (mounted) setState(() {});
  }

  // Status changes are pushed as they happen (Wi-Fi or Bluetooth link up/down)
  void _handlePeerUpdate(Map<String, dynamic> update) {
    if (!mounted) return;
    peers = api.peers;
    _filterPeers();
  }

  // Keeps each row's last-message preview current, including messages we send
  void _handleHistoryChanged(String _) {
    if (mounted) setState(() {});
  }

  Future<void> _loadPeers() async {
    try {
      final loadedPeers = await api.getPeers();
      if (mounted) {
        setState(() {
          peers = loadedPeers;
          _isLoading = false;
        });
        _filterPeers();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _refresh() {
    setState(() => _isLoading = true);
    _loadPeers();
  }

  void _filterPeers() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        filteredPeers = List.from(peers);
      } else {
        filteredPeers = peers.where((peer) {
          // The name may be a private alias; the handle they chose still finds them
          final name = peer['name'].toString().toLowerCase();
          final handle = (peer['handle'] as String? ?? '').toLowerCase();
          final id = peer['id'].toString().toLowerCase();
          return name.contains(query) || handle.contains(query) || id.contains(query);
        }).toList();
      }
    });
  }

  void _openChat(Map<String, dynamic> peer) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(peerName: peer['name'] as String, peerId: peer['id'] as String)),
    );
  }

  @override
  void dispose() {
    api.removeOnPeerUpdate(_handlePeerUpdate);
    api.removeOnHistoryChanged(_handleHistoryChanged);
    _drafts.removeListener(_handleDraftsChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anyoneOnline = peers.any((p) => p['online'] == true);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const BrandMark(size: 30),
            const SizedBox(width: 10),
            // The wordmark shrinks to fit rather than truncating at large text sizes
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Chatter', style: theme.textTheme.headlineMedium),
              ),
            ),
          ],
        ),
        actions: [
          const WifiQrButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh peers',
            onPressed: _isLoading ? null : _refresh,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPeers,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(child: MeshMap(peers: peers, myName: api.myHandle ?? '')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(MeshMap.summary(peers), style: theme.textTheme.titleSmall),
                    if (anyoneOnline) ...[
                      const SizedBox(height: 8),
                      const MeshLegend(),
                    ],
                  ],
                ),
              ),
            ),
            if (peers.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search by name or peer ID',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Clear search',
                              onPressed: _searchController.clear,
                            ),
                    ),
                  ),
                ),
              ),
            // Reserved height, so the list doesn't jump when a refresh starts
            SliverToBoxAdapter(
              child: SizedBox(
                height: 2,
                child: _isLoading && peers.isNotEmpty ? const LinearProgressIndicator(minHeight: 2) : null,
              ),
            ),
            ..._buildBody(),
            const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_isLoading && peers.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: StateMessage(fill: false, leading: CircularProgressIndicator(), title: 'Looking for your contacts'),
        ),
      ];
    }
    if (peers.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: StateMessage(
            fill: false,
            title: 'No chats yet',
            body: 'Find phones running Chatter in the Nearby tab, or scan a friend\'s Wi-Fi code with the QR '
                'button above.',
            action: OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Check again'),
              onPressed: _refresh,
            ),
          ),
        ),
      ];
    }
    if (filteredPeers.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: StateMessage(
            fill: false,
            icon: Icons.search_off,
            title: 'No one matches "${_searchController.text.trim()}"',
            body: 'Try a handle, or the first few characters of a peer ID.',
          ),
        ),
      ];
    }
    return [
      SliverList.separated(
        itemCount: filteredPeers.length,
        separatorBuilder: (_, __) => const Divider(indent: 86, endIndent: 20),
        itemBuilder: (context, index) {
          final peer = filteredPeers[index];
          final history = api.historyFor(peer['id'] as String);
          return _PeerRow(
            key: ValueKey(peer['id']),
            peer: peer,
            lastMessage: history.isEmpty ? null : history.last,
            draft: _drafts.getDraft(peer['id'] as String),
            onTap: () => _openChat(peer),
            onLongPress: () => showPeerIdentitySheet(context, peer['id'] as String),
          );
        },
      ),
    ];
  }
}

/// One conversation in the list: who, how they're reachable, the latest
/// message and how many are unread.
class _PeerRow extends StatelessWidget {
  final Map<String, dynamic> peer;
  final Map<String, dynamic>? lastMessage;
  final String draft;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PeerRow({
    super.key,
    required this.peer,
    required this.lastMessage,
    required this.draft,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final id = peer['id'] as String;
    final name = peer['name'] as String? ?? 'Peer';
    final isOnline = peer['online'] == true;
    final unread = peer['unread'] as int? ?? 0;
    final last = lastMessage;

    final String preview;
    if (last == null) {
      preview = reachSentence(peer);
    } else {
      final content = markdownToPlain(last['content'] as String? ?? '');
      preview = last['isOutgoing'] == true
          ? switch (last['status']) {
              'failed' => 'Not delivered: $content',
              'queued' => 'Waiting to send: $content',
              _ => 'You: $content',
            }
          : content;
    }
    final time = last == null ? null : formatListTime(context, last['timestamp'] as DateTime);

    final verified = peer['verified'] == true;
    final conflict = peer['handleConflict'] == true;
    final label = [
      name,
      if (verified) 'verified contact',
      if (conflict) 'impersonation warning: this handle is also claimed by another device',
      reachSentence(peer),
      if (unread > 0) '$unread unread',
      if (draft.isNotEmpty) 'draft: ${draft.replaceAll('\n', ' ')}'
      else if (last != null) 'last message $time: $preview',
    ].join(', ');

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      onLongPressHint: 'Show identity',
      onLongPress: onLongPress,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              PeerAvatar(peerId: id, name: name, online: isOnline, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              if (verified || conflict) ...[
                                const SizedBox(width: 6),
                                TrustMark.of(peer, size: 16),
                              ],
                            ],
                          ),
                        ),
                        if (time != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: unread > 0 ? cs.primary : cs.onSurfaceVariant,
                              fontWeight: unread > 0 ? FontWeight.w600 : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(child: _PreviewLine(text: preview, draft: draft, emphasised: unread > 0)),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          Badge(
                            label: Text(unread > 99 ? '99+' : '$unread'),
                            largeSize: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            textStyle: theme.textTheme.labelMedium,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The second line of a conversation row: the latest message, or, while
/// something is typed and not sent, the draft, which takes precedence.
class _PreviewLine extends StatelessWidget {
  final String text;
  final String draft;
  final bool emphasised;

  const _PreviewLine({required this.text, required this.draft, required this.emphasised});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.bodyMedium!.copyWith(
      color: emphasised ? cs.onSurface : cs.onSurfaceVariant,
      fontWeight: emphasised ? FontWeight.w600 : null,
    );
    if (draft.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Draft: ', style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
        TextSpan(text: draft.replaceAll('\n', ' ')),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
