import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../application_api.dart';
import '../services/api_service.dart';
import '../services/draft_store.dart';
import '../services/link_preview_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/link_preview_card.dart';
import '../widgets/message_text.dart';
import '../widgets/peer_display.dart';
import '../widgets/peer_identity.dart';
import '../widgets/time_format.dart';

/// A conversation: with one peer, or in a channel when [peerId] is a
/// channel's conversation ID (see [ApplicationAPI.channelConversation]).
class ChatScreen extends StatefulWidget {
  final String peerName;
  final String peerId;

  /// The conversation on screen, if any: its messages don't need a notification.
  static String? visiblePeerId;

  const ChatScreen({
    super.key,
    required this.peerName,
    required this.peerId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApplicationAPI api = ApplicationAPI();
  final DraftStore _drafts = DraftStore();
  // Live status: name (handle) and which transports reach the peer right now
  late Map<String, dynamic> _status;
  // The stored conversation; ApplicationAPI owns it and tells us when it changes
  List<Map<String, dynamic>> _messages = const [];
  bool _isSending = false;
  // The list is reversed, so offset 0 is the newest message. Away from it,
  // arrivals are counted instead of yanking the reader down.
  bool _awayFromLatest = false;
  int _unseen = 0;
  bool _hasDraft = false;
  late final bool _isChannel = ApplicationAPI.isChannel(widget.peerId);
  // The channel's name, privacy and unread count; null for a direct chat
  Map<String, dynamic>? _channel;

  static const _nearLatest = 160.0;

  @override
  void initState() {
    super.initState();
    ChatScreen.visiblePeerId = widget.peerId;
    _status = _isChannel ? const {} : api.peerStatus(widget.peerId);
    _channel = api.channelStatus(widget.peerId);
    _messages = api.historyFor(widget.peerId);
    // Whatever was being typed here last time, left or not
    _msgController.text = _drafts.getDraft(widget.peerId);
    _hasDraft = _msgController.text.trim().isNotEmpty;

    api.onPeerUpdate(_handlePeerUpdate);
    api.onHistoryChanged(_handleHistoryChanged);
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
    _msgController.addListener(_handleDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markRead();
    });
  }

  void _handlePeerUpdate(Map<String, dynamic> update) {
    if (!mounted) return;
    if (_isChannel) {
      setState(() {}); // an author's name or trust badge may have changed
    } else if (update['id'] == widget.peerId) {
      setState(() => _status = update);
    }
  }

  void _handleHistoryChanged(String peerId) {
    if (!mounted || peerId != widget.peerId) return;
    final next = api.historyFor(peerId);
    final added = next.length - _messages.length;
    final sentByMe = added > 0 && next.last['isOutgoing'] == true;
    setState(() {
      _channel = api.channelStatus(widget.peerId);
      _messages = next;
      if (added > 0 && _awayFromLatest && !sentByMe) _unseen += added;
    });
    if (added > 0) {
      // Our own message always comes into view; others only if we're at the end
      if (sentByMe) _scrollToBottom();
      _markRead(); // arrived while we're looking at the chat
    }
  }

  void _handleScroll() {
    final away = _scrollController.offset > _nearLatest;
    if (away != _awayFromLatest) {
      setState(() {
        _awayFromLatest = away;
        if (!away) _unseen = 0;
      });
    }
  }

  // Keeps the draft for when the user comes back, and rebuilds the send
  // button when it goes between empty and not
  void _handleDraftChanged() {
    _drafts.setDraft(widget.peerId, _msgController.text);
    final hasText = _msgController.text.trim().isNotEmpty;
    if (hasText != _hasDraft) setState(() => _hasDraft = hasText);
  }

  // Only count messages as read while the user can actually see them
  void _markRead() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) {
      api.markRead(widget.peerId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _markRead();
    // The app may be killed in the background; don't wait for the save timer
    if (state == AppLifecycleState.paused) _drafts.flush();
  }

  bool get _isOnline => _status['online'] == true;

  String get _peerName =>
      _isChannel ? '#${_channel?['name'] ?? widget.peerName}' : _status['name'] as String? ?? widget.peerName;

  bool get _isPrivateChannel => _channel?['private'] == true;

  Future<void> _leaveChannel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave $_peerName?'),
        content: Text(_isPrivateChannel
            ? 'You\'ll stop seeing its posts. To come back, you\'ll need its name and passphrase again.'
            : 'You\'ll stop seeing its posts. You can join again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    await api.leaveChannel(widget.peerId);
    _drafts.clearDraft(widget.peerId);
    if (mounted) Navigator.of(context).pop();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  /// The draft as it should go out: trailing whitespace and leading blank
  /// lines dropped; line breaks and indentation inside it kept.
  static String _outgoingText(String draft) => draft.trimRight().replaceFirst(RegExp(r'^\s*\n'), '');

  Future<void> _handleSend() async {
    final text = _outgoingText(_msgController.text);
    if (text.isEmpty || _isSending) return;

    _msgController.clear();
    _drafts.clearDraft(widget.peerId); // it's in the thread now
    setState(() => _isSending = true);

    try {
      // Adds the message to the conversation right away, then updates its status
      final status = await api.sendMessage(text, widget.peerId);
      if (status == 'queued' && mounted) {
        showNotice(context, 'No one in range right now. Chatter keeps the message and sends it when someone is nearby.');
      }
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Not delivered. ${e is ApiException ? e.message : e}',
          tone: NoticeTone.error,
          duration: const Duration(seconds: 4),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showIdentity() {
    FocusScope.of(context).unfocus();
    showPeerIdentitySheet(context, widget.peerId);
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    showNotice(context, 'Message copied', tone: NoticeTone.success, duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ChatScreen.visiblePeerId == widget.peerId) ChatScreen.visiblePeerId = null;
    api.removeOnPeerUpdate(_handlePeerUpdate);
    api.removeOnHistoryChanged(_handleHistoryChanged);
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final verified = _status['verified'] == true;
    final conflict = _status['handleConflict'] == true;

    return Scaffold(
      appBar: _isChannel ? _buildChannelAppBar(theme) : AppBar(
        titleSpacing: 0,
        title: Semantics(
          header: true,
          button: true,
          label: [
            _peerName,
            if (verified) 'verified contact',
            if (conflict) 'impersonation warning',
            reachSentence(_status),
          ].join(', '),
          onTapHint: 'Show identity',
          onTap: _showIdentity,
          excludeSemantics: true,
          child: InkWell(
            onTap: _showIdentity,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                PeerAvatar(peerId: widget.peerId, name: _peerName, online: _isOnline, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _peerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          if (verified || conflict) ...[
                            const SizedBox(width: 6),
                            TrustMark.of(_status),
                          ],
                        ],
                      ),
                      Text(
                        reachSentence(_status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: _isOnline ? ChatterColors.of(context).reach : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Peer identity',
            onPressed: _showIdentity,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outlineVariant),
        ),
      ),
      body: Column(
        children: [
          if (conflict) ImpersonationWarning(onTap: _showIdentity),
          Expanded(
            child: _messages.isEmpty ? _buildEmptyThread() : _buildThread(),
          ),
          _Composer(
            controller: _msgController,
            peerName: _peerName,
            canSend: _hasDraft && !_isSending,
            onSend: _handleSend,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildChannelAppBar(ThemeData theme) {
    final cs = theme.colorScheme;
    final about = _isPrivateChannel
        ? 'Private: only phones with the passphrase can read it'
        : 'Open: every phone in range can read it';
    return AppBar(
      titleSpacing: 0,
      title: Semantics(
        header: true,
        label: '$_peerName channel, $about',
        excludeSemantics: true,
        child: Row(
          children: [
            ChannelAvatar(private: _isPrivateChannel, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_peerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
                  Text(
                    about,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        PopupMenuButton<void>(
          tooltip: 'Channel options',
          itemBuilder: (_) => [
            PopupMenuItem(onTap: _leaveChannel, child: const Text('Leave channel')),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: cs.outlineVariant),
      ),
    );
  }

  Widget _buildEmptyThread() {
    if (_isChannel) {
      return StateMessage(
        icon: _isPrivateChannel ? Icons.lock_outline : Icons.tag,
        title: 'Nothing in $_peerName yet',
        body: _isPrivateChannel
            ? 'Posts here hop from phone to phone, but only phones that joined with the passphrase can read them.'
            : 'Posts here reach every phone in range running Chatter, and hop on through them to phones further away.',
      );
    }
    return StateMessage(
      icon: Icons.lock_outline,
      title: 'Start your conversation with $_peerName',
      body: 'Messages go straight to their phone over Wi-Fi or Bluetooth, '
          'or hop through other phones running Chatter.',
    );
  }

  Widget _buildThread() {
    // Chronological entries: a day heading before each new day's first message
    final entries = <Object>[];
    String? newestOutgoingId;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final time = m['timestamp'] as DateTime;
      if (i == 0 || !isSameDay(_messages[i - 1]['timestamp'] as DateTime, time)) {
        entries.add(time);
      }
      entries.add(i);
      // Failed messages always say so; the status word goes on the newest that went out
      if (m['isOutgoing'] == true && m['status'] != 'failed') newestOutgoingId = m['id'] as String;
    }

    bool continuesGroup(int a, int b) {
      if (b < 0 || b >= _messages.length) return false;
      final x = _messages[a], y = _messages[b];
      final gap = (x['timestamp'] as DateTime).difference(y['timestamp'] as DateTime).abs();
      return x['isOutgoing'] == y['isOutgoing'] &&
          x['author'] == y['author'] && // in a channel, one burst is one person's
          gap < const Duration(minutes: 3) &&
          isSameDay(x['timestamp'] as DateTime, y['timestamp'] as DateTime);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleMax = (constraints.maxWidth * 0.8).clamp(0.0, 560.0);
        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              reverse: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[entries.length - 1 - index];
                if (entry is DateTime) {
                  return _DayHeading(key: ValueKey('day-${entry.toLocal().toIso8601String()}'), time: entry);
                }
                final i = entry as int;
                final m = _messages[i];
                final author = m['author'] as String?;
                return _MessageBubble(
                  key: ValueKey(m['id']),
                  message: m,
                  peerName: author != null ? api.displayName(author) : _peerName,
                  // In a channel, who wrote it heads each burst: anyone can pick
                  // a name, so the end of their peer ID and any badge go with it
                  author: author != null && m['isOutgoing'] != true && !continuesGroup(i, i - 1)
                      ? _AuthorLine(
                          peerId: author,
                          name: api.displayName(author),
                          verified: api.isVerified(author),
                          conflict: api.hasHandleConflict(author),
                          onTap: () => showPeerIdentitySheet(context, author),
                        )
                      : null,
                  maxWidth: bubbleMax,
                  groupedWithPrevious: continuesGroup(i, i - 1),
                  groupedWithNext: continuesGroup(i, i + 1),
                  showStatusWord: m['id'] == newestOutgoingId,
                  onCopy: () => _copyMessage(m['content'] as String? ?? ''),
                );
              },
            ),
            if (_awayFromLatest)
              Positioned(
                right: 16,
                bottom: 12,
                child: _unseen > 0
                    ? FilledButton.tonalIcon(
                        onPressed: _scrollToBottom,
                        icon: const Icon(Icons.arrow_downward, size: 20),
                        label: Text(_unseen == 1 ? '1 new message' : '$_unseen new messages'),
                      )
                    : IconButton.filledTonal(
                        onPressed: _scrollToBottom,
                        tooltip: 'Jump to latest',
                        icon: const Icon(Icons.arrow_downward),
                      ),
              ),
          ],
        );
      },
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DayHeading extends StatelessWidget {
  final DateTime time;
  const _DayHeading({super.key, required this.time});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Semantics(
          header: true,
          child: Text(
            formatDayHeading(time),
            style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Words and icons for an outgoing message's progress. Every state has its
/// own icon shape, so none of them depends on colour.
({IconData icon, String word}) _deliveryOf(String? status) => switch (status) {
      'read' => (icon: Icons.visibility_outlined, word: 'Read'),
      'delivered' => (icon: Icons.done_all, word: 'Delivered'),
      'sent' => (icon: Icons.check, word: 'Sent'),
      'queued' => (icon: Icons.hourglass_empty, word: 'Waiting'),
      'failed' => (icon: Icons.error_outline, word: 'Not delivered'),
      _ => (icon: Icons.schedule, word: 'Sending'),
    };

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final String peerName;
  final double maxWidth;
  final bool groupedWithPrevious;
  final bool groupedWithNext;
  final bool showStatusWord;
  final VoidCallback onCopy;

  /// Who wrote it, shown at the top (channels only).
  final _AuthorLine? author;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.peerName,
    required this.maxWidth,
    required this.groupedWithPrevious,
    required this.groupedWithNext,
    required this.showStatusWord,
    required this.onCopy,
    this.author,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chatter = ChatterColors.of(context);
    final isOut = message['isOutgoing'] == true;
    final failed = isOut && message['status'] == 'failed';
    final content = message['content'] as String? ?? '';
    final timeStr = formatClock(context, message['timestamp'] as DateTime);
    final delivery = _deliveryOf(message['status'] as String?);
    final link = firstWebLink(content);

    final Color bg;
    final Color fg;
    if (failed) {
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
    } else if (isOut) {
      bg = chatter.bubbleOut;
      fg = chatter.onBubbleOut;
    } else {
      bg = chatter.bubbleIn;
      fg = chatter.onBubbleIn;
    }
    final meta = fg.withValues(alpha: 0.78);

    // Rounded all round, tighter on the sender's side where bubbles of one
    // burst meet; the last of a burst gets the brand mark's tail
    const big = Radius.circular(20);
    const small = Radius.circular(6);
    final radius = BorderRadius.only(
      topLeft: !isOut && groupedWithPrevious ? small : big,
      topRight: isOut && groupedWithPrevious ? small : big,
      bottomLeft: !isOut ? small : big,
      bottomRight: isOut ? small : big,
    );
    final tail = groupedWithNext ? null : (isOut ? _Tail.right : _Tail.left);

    final statusText = isOut ? (showStatusWord || failed ? delivery.word : null) : null;
    // A burst from the other person shows its time once, on the last bubble;
    // ours always show it, since each carries its own delivery status
    final showMeta = isOut || !groupedWithNext;
    final semanticLabel = [
      isOut ? 'You' : peerName,
      if (author?.verified == true) 'verified contact',
      if (author?.conflict == true) 'impersonation warning',
      timeStr,
      if (isOut) delivery.word,
      content,
      if (link != null) 'link to ${link.host}',
    ].join(', ');

    return Padding(
      padding: EdgeInsets.only(top: groupedWithPrevious ? 2 : 10),
      child: Align(
        alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Semantics(
            label: semanticLabel,
            onLongPressHint: 'Copy message',
            onLongPress: onCopy,
            customSemanticsActions: {
              if (author != null) const CustomSemanticsAction(label: 'Show who wrote it'): author!.onTap,
              if (link != null)
                CustomSemanticsAction(label: 'Open link to ${link.host}'): () =>
                    openLinkWithConsent(context, link.url.toString(), text: link.text),
            },
            excludeSemantics: true,
            child: Material(
              color: bg,
              shape: _BubbleBorder(
                radius: radius,
                tail: tail,
                side: !isOut && theme.brightness == Brightness.light
                    ? BorderSide(color: cs.outlineVariant)
                    : BorderSide.none,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onLongPress: onCopy,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 9, 14, showMeta ? 8 : 9),
                  // As wide as the longer of the text and the time line, so
                  // the time sits at the bubble's trailing edge either way
                  child: IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (author != null) ...[author!, const SizedBox(height: 4)],
                        MessageText(content, style: theme.textTheme.bodyLarge!.copyWith(color: fg)),
                        if (link != null) ...[
                          const SizedBox(height: 8),
                          LinkPreviewCard(link: link, foreground: fg),
                        ],
                        if (showMeta) ...[
                          const SizedBox(height: 4),
                          // Gaps are padding, not Wrap.spacing: Wrap leaves spacing
                          // out of its intrinsic width, which made short bubbles
                          // too narrow and pushed the tick onto its own line
                          Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(timeStr, style: theme.textTheme.bodySmall!.copyWith(color: meta)),
                              if (isOut)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(delivery.icon, size: MediaQuery.textScalerOf(context).scale(15), color: meta),
                                ),
                              if (statusText != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    statusText,
                                    style: theme.textTheme.bodySmall!.copyWith(color: fg, fontWeight: FontWeight.w600),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top line of a channel post: the author's node, name and badge, and
/// the end of their peer ID, which no one else can copy. Opens their identity.
class _AuthorLine extends StatelessWidget {
  final String peerId;
  final String name;
  final bool verified;
  final bool conflict;
  final VoidCallback onTap;

  const _AuthorLine({
    required this.peerId,
    required this.name,
    required this.verified,
    required this.conflict,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = ChatterColors.of(context).onBubbleIn;
    final idTail = peerId.length > 6 ? '…${peerId.substring(peerId.length - 6)}' : peerId;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: PeerAvatar(peerId: peerId, name: name, size: 20),
          ),
          Text(name, style: theme.textTheme.labelLarge!.copyWith(color: fg, fontWeight: FontWeight.w700)),
          if (verified || conflict)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TrustMark(verified: verified, conflict: conflict, size: 16),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              idTail,
              style: theme.textTheme.bodySmall!.copyWith(color: fg.withValues(alpha: 0.78), fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final String peerName;
  final bool canSend;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.peerName,
    required this.canSend,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const pill = BorderRadius.all(Radius.circular(24));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  // Enter starts a new line (lists, addresses, triage notes);
                  // only the Send button sends
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message $peerName',
                    hintMaxLines: 1,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(borderRadius: pill, borderSide: BorderSide(color: cs.outlineVariant)),
                    enabledBorder:
                        OutlineInputBorder(borderRadius: pill, borderSide: BorderSide(color: cs.outlineVariant)),
                    focusedBorder: OutlineInputBorder(borderRadius: pill, borderSide: BorderSide(color: cs.primary, width: 2)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: canSend ? onSend : null,
                tooltip: 'Send',
                iconSize: 22,
                // The accent (ember) in every theme: sending is what lights your messages up
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(48),
                  backgroundColor: ChatterColors.of(context).accent,
                  foregroundColor: ChatterColors.of(context).onAccent,
                ),
                icon: const Icon(Icons.arrow_upward),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Tail { left, right }

/// A message bubble: a rounded rectangle, plus on the last bubble of a burst
/// a tail at the sender's lower corner, cut like the one on Chatter's mark.
class _BubbleBorder extends OutlinedBorder {
  final BorderRadius radius;
  final _Tail? tail;

  const _BubbleBorder({required this.radius, this.tail, super.side});

  Path _path(Rect rect) {
    final body = Path()..addRRect(radius.toRRect(rect));
    if (tail == null) return body;
    final b = rect.bottom;
    // Leans outward and down from the corner, like the mark's tail
    final shape = tail == _Tail.left
        ? (Path()
          ..moveTo(rect.left + 2, b - 16)
          ..lineTo(rect.left - 6, b + 4)
          ..lineTo(rect.left + 18, b)
          ..close())
        : (Path()
          ..moveTo(rect.right - 2, b - 16)
          ..lineTo(rect.right + 6, b + 4)
          ..lineTo(rect.right - 18, b)
          ..close());
    return Path.combine(PathOperation.union, body, shape);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect), side.toPaint());
  }

  @override
  _BubbleBorder copyWith({BorderSide? side}) => _BubbleBorder(radius: radius, tail: tail, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => _BubbleBorder(radius: radius * t, tail: tail, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is _BubbleBorder && other.radius == radius && other.tail == tail && other.side == side;

  @override
  int get hashCode => Object.hash(radius, tail, side);
}
