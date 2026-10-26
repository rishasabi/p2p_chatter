import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application_api.dart';
import '../theme/app_theme.dart';
import 'feedback.dart';
import 'peer_display.dart';
import 'time_format.dart';

/// Peer IDs are keys, not names: monospace so similar ones can be compared
/// character by character.
const _idStyle = TextStyle(fontFamily: 'monospace');

/// Copies the full [peerId], with a buzz and a notice to say it worked.
void copyPeerId(BuildContext context, String peerId) {
  Clipboard.setData(ClipboardData(text: peerId));
  HapticFeedback.lightImpact();
  showNotice(context, 'Peer ID copied to clipboard', tone: NoticeTone.success, duration: const Duration(seconds: 2));
}

/// The small mark after a peer's name: a check for a verified contact, a
/// warning sign for a handle another device claims. Nothing otherwise.
class TrustMark extends StatelessWidget {
  final bool verified;
  final bool conflict;
  final double size;

  /// What a screen reader says for the warning sign.
  final String conflictLabel;

  const TrustMark({
    super.key,
    required this.verified,
    required this.conflict,
    this.size = 18,
    this.conflictLabel = 'Impersonation warning',
  });

  /// From an [ApplicationAPI.peerStatus] map.
  TrustMark.of(Map<String, dynamic> status, {Key? key, double size = 18})
      : this(key: key, verified: status['verified'] == true, conflict: status['handleConflict'] == true, size: size);

  @override
  Widget build(BuildContext context) {
    final chatter = ChatterColors.of(context);
    if (verified) {
      return Icon(Icons.verified, size: size, color: chatter.verified, semanticLabel: 'Verified contact');
    }
    if (conflict) {
      return Icon(Icons.warning_amber_rounded, size: size, color: chatter.warning, semanticLabel: conflictLabel);
    }
    return const SizedBox.shrink();
  }
}

/// Says that a peer's handle is also claimed by another device, so the name
/// alone can't be trusted. With [onTap] it is a strip that opens their
/// identity, held to a few lines so it never crowds out the chat.
class ImpersonationWarning extends StatelessWidget {
  final VoidCallback? onTap;

  const ImpersonationWarning({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatter = ChatterColors.of(context);
    final fg = chatter.onWarningContainer;
    final strip = onTap != null;

    return Semantics(
      container: true,
      button: strip,
      onTapHint: strip ? 'Check their peer ID' : null,
      child: Material(
        color: chatter.warningContainer,
        borderRadius: strip ? null : BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Impersonation warning: ', style: TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: 'this handle is also claimed by another device on the network.'),
                      if (strip) const TextSpan(text: ' Check their peer ID.'),
                    ]),
                    maxLines: strip ? 3 : null,
                    overflow: strip ? TextOverflow.ellipsis : null,
                    style: theme.textTheme.bodyMedium!.copyWith(color: fg),
                  ),
                ),
                if (strip) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Who [peerId] really is: their peer ID (the one thing nobody else can
/// claim), whether this user has verified it, and a private name for them.
Future<void> showPeerIdentitySheet(BuildContext context, String peerId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _PeerIdentitySheet(peerId: peerId),
    );

class _PeerIdentitySheet extends StatefulWidget {
  final String peerId;
  const _PeerIdentitySheet({required this.peerId});

  @override
  State<_PeerIdentitySheet> createState() => _PeerIdentitySheetState();
}

class _PeerIdentitySheetState extends State<_PeerIdentitySheet> {
  final ApplicationAPI api = ApplicationAPI();
  late final TextEditingController _aliasController;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(text: api.aliasOf(widget.peerId) ?? '');
    api.onPeerUpdate(_handlePeerUpdate);
  }

  void _handlePeerUpdate(Map<String, dynamic> update) {
    if (mounted && update['id'] == widget.peerId) setState(() {});
  }

  // A notice would show under the sheet, so the button itself says it worked
  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.peerId));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    api.removeOnPeerUpdate(_handlePeerUpdate);
    _copiedTimer?.cancel();
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chatter = ChatterColors.of(context);
    final peerId = widget.peerId;
    final status = api.peerStatus(peerId);
    final name = status['name'] as String;
    final handle = api.handleOf(peerId);
    final verified = status['verified'] == true;
    final seen = api.firstSeen(peerId);
    final secondary = theme.textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant);

    return Padding(
      // Keeps the name field above the keyboard
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                PeerAvatar(peerId: peerId, name: name, online: status['online'] == true, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: name),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: TrustMark.of(status, size: 22),
                          ),
                        ),
                      ]),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(handle != null ? 'Advertised handle: @$handle' : 'Hasn\'t shared a handle', style: secondary),
            const SizedBox(height: 2),
            Text(
              seen != null ? 'First seen: ${formatDayHeading(seen)}, ${formatClock(context, seen)}' : 'First seen: not recorded',
              style: secondary,
            ),
            if (status['handleConflict'] == true) ...[
              const SizedBox(height: 16),
              const ImpersonationWarning(),
            ],
            const SizedBox(height: 20),
            Text('Peer ID', style: theme.textTheme.titleSmall!.copyWith(color: cs.primary)),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(peerId, style: theme.textTheme.bodyLarge!.merge(_idStyle)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This is their phone\'s cryptographic key. Anyone can pick any handle, but nobody else can use this ID.',
              style: theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 20),
                label: Semantics(liveRegion: true, child: Text(_copied ? 'Copied' : 'Copy peer ID')),
              ),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.verified, color: verified ? chatter.verified : cs.onSurfaceVariant),
              title: const Text('Verified contact'),
              subtitle: const Text('Turn on only after checking this ID against the one on their phone, in person.'),
              value: verified,
              onChanged: (v) => api.setVerified(peerId, v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _aliasController,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Your name for them',
                hintText: handle,
                helperText: 'Only on this phone. Shown instead of the name they chose, which can\'t change it.',
                helperMaxLines: 3,
              ),
              onChanged: (v) => api.setAlias(peerId, v),
            ),
          ],
        ),
      ),
    );
  }
}
