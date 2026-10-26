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
import 'delete_conversation_dialog.dart';
import 'join_channel_dialog.dart';
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
  // Direct messages, or mesh channels
  bool _showChannels = false;

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

  // Keeps each row's last-message preview current, including messages we
  // send, and moves the conversation that just changed to the top
  void _handleHistoryChanged(String _) {
    if (!mounted) return;
    peers = api.peers;
    _filterPeers();
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
            SliverToBoxAdapter(
              child: ValueListenableBuilder(
                valueListenable: api.myHandleListenable, // renamed in Settings
                builder: (context, handle, _) => MeshMap(peers: peers, myName: handle ?? ''),
              ),
            ),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, icon: const Icon(Icons.person_outline), label: Text(_tabLabel('Direct', false))),
                    ButtonSegment(value: true, icon: const Icon(Icons.tag), label: Text(_tabLabel('Channels', true))),
                  ],
                  selected: {_showChannels},
                  onSelectionChanged: (s) => setState(() => _showChannels = s.first),
                ),
              ),
            ),
            if (peers.isNotEmpty || _showChannels)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: _showChannels ? 'Search channels' : 'Search by name or peer ID',
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

  /// A segment's label, with how many messages in it are unread.
  String _tabLabel(String label, bool channels) {
    final unread = channels
        ? api.channels.fold<int>(0, (n, c) => n + (c['unread'] as int))
        : peers.fold<int>(0, (n, p) => n + (p['unread'] as int? ?? 0));
    return unread > 0 ? '$label · $unread' : label;
  }

  void _openChannel(Map<String, dynamic> channel) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(peerName: channel['name'] as String, peerId: channel['id'] as String)),
    );
  }

  /// What a long press on a conversation offers: a peer's identity, and
  /// deleting the chat (or leaving and deleting the channel).
  Future<void> _showConversationMenu(String id, {required bool channel}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!channel)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Peer identity'),
                onTap: () => Navigator.pop(context, 'identity'),
              ),
            ListTile(
              title: DangerMenuLabel(
                channel ? Icons.logout : Icons.delete_outline,
                channel ? 'Leave & delete channel' : 'Delete chat',
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'identity') showPeerIdentitySheet(context, id);
    if (choice == 'delete') await confirmDeleteConversation(context, id);
  }

  List<Widget> _buildChannels() {
    final query = _searchController.text.toLowerCase().trim().replaceFirst(RegExp(r'^#'), '');
    final shown = api.channels.where((c) => (c['name'] as String).contains(query)).toList();
    return [
      SliverToBoxAdapter(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: const ChannelAvatar(private: false, size: 52),
          title: const Text('Join or create a channel'),
          subtitle: const Text('Open to everyone in range, or private with a passphrase'),
          trailing: const Icon(Icons.add),
          onTap: () => showJoinChannelDialog(context),
        ),
      ),
      if (shown.isEmpty)
        SliverToBoxAdapter(
          child: StateMessage(
            fill: false,
            icon: Icons.search_off,
            title: query.isEmpty ? 'You haven\'t joined any channels' : 'No channel matches "#$query"',
            body: query.isEmpty ? null : 'You can join it: channels are made by posting to them.',
          ),
        )
      else
        SliverList.separated(
          itemCount: shown.length,
          separatorBuilder: (_, __) => const Divider(indent: 86, endIndent: 20),
          itemBuilder: (context, index) {
            final channel = shown[index];
            final id = channel['id'] as String;
            final history = api.historyFor(id);
            final last = history.isEmpty ? null : history.last;
            final author = last?['author'] as String?;
            return _ChannelRow(
              key: ValueKey(id),
              channel: channel,
              lastMessage: last,
              lastAuthor: author != null ? api.displayName(author) : null,
              draft: _drafts.getDraft(id),
              onTap: () => _openChannel(channel),
              onLongPress: () => _showConversationMenu(id, channel: true),
            );
          },
        ),
    ];
  }

  List<Widget> _buildBody() {
    if (_showChannels) return _buildChannels();
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
            onLongPress: () => _showConversationMenu(peer['id'] as String, channel: false),
          );
        },
      ),
    ];
  }
}

/// The latest message as a one-line preview, saying who wrote it when it's
/// ours or ([from]) someone's in a channel.
String _previewOf(Map<String, dynamic> last, {String? from}) {
  final content = markdownToPlain(last['content'] as String? ?? '');
  if (last['isOutgoing'] == true) {
    return switch (last['status']) {
      'failed' => 'Not delivered: $content',
      'queued' => 'Waiting to send: $content',
      _ => 'You: $content',
    };
  }
  return from != null ? '$from: $content' : content;
}

/// One channel in the list: its name, the latest post and who wrote it, and
/// how many are unread.
class _ChannelRow extends StatelessWidget {
  final Map<String, dynamic> channel;
  final Map<String, dynamic>? lastMessage;
  final String? lastAuthor;
  final String draft;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ChannelRow({
    super.key,
    required this.channel,
    required this.lastMessage,
    required this.lastAuthor,
    required this.draft,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = '#${channel['name']}';
    final private = channel['private'] == true;
    final unread = channel['unread'] as int? ?? 0;
    final last = lastMessage;
    final preview = last == null
        ? (private ? 'Private channel' : 'Open channel')
        : _previewOf(last, from: lastAuthor);
    final time = last == null ? null : formatListTime(context, last['timestamp'] as DateTime);

    final label = [
      '$name channel',
      if (private) 'private',
      if (unread > 0) '$unread unread',
      if (draft.isNotEmpty) 'draft: ${draft.replaceAll('\n', ' ')}'
      else if (last != null) 'last message $time: $preview',
    ].join(', ');

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      onLongPressHint: 'Leave and delete',
      onLongPress: onLongPress,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              ChannelAvatar(private: private, size: 52),
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
                          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
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

    final preview = last == null ? reachSentence(peer) : _previewOf(last);
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
      onLongPressHint: 'Identity or delete',
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
