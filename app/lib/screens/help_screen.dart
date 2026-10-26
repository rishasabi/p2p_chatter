import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/mesh_map.dart';

/// What the app's icons and lines mean: message status, how you're connected
/// to someone, and the trust badges. Reached from Settings.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chatter = ChatterColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & guides')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Section(
            title: 'Message status',
            intro: 'The icon under each message you send shows how far it has got.',
          ),
          _Card(children: [
            const _Entry(
              leading: _IconBadge(Icons.schedule),
              title: 'Sending',
              body: 'Leaving this phone.',
            ),
            const _Entry(
              leading: _IconBadge(Icons.hourglass_empty),
              title: 'Waiting',
              body: 'No one in range yet. Chatter keeps it for up to a day and sends it as soon as '
                  'someone is; other phones carry it on too.',
            ),
            const _Entry(
              leading: _IconBadge(Icons.check),
              title: 'Sent',
              body: 'Handed to the mesh: straight to their phone, or to phones that pass it on.',
            ),
            const _Entry(
              leading: _IconBadge(Icons.done_all),
              title: 'Delivered',
              body: 'Their phone confirmed it arrived.',
            ),
            const _Entry(
              leading: _IconBadge(Icons.visibility_outlined),
              title: 'Read',
              body: 'They opened the chat. They can turn read receipts off, so this may never show.',
            ),
            _Entry(
              leading: _IconBadge(Icons.error_outline, color: cs.error),
              title: 'Not delivered',
              body: 'Chatter couldn\'t hand it to the mesh. It tries again for a day each time the app starts.',
            ),
          ]),
          const _Section(
            title: 'How you\'re connected',
            intro: 'On the Chats map, the line between you and someone shows how a message reaches them.',
          ),
          const _Card(children: [
            _Entry(
              leading: _LineBadge(MeshLink.wifi),
              title: 'Wi-Fi',
              body: 'Both phones on the same Wi-Fi network or phone hotspot. The fastest link. Connect by '
                  'scanning someone\'s code with the QR button at the top of Chats or Nearby.',
            ),
            _Entry(
              leading: _LineBadge(MeshLink.bluetooth),
              title: 'Bluetooth',
              body: 'Phone to phone, with no network at all, at shorter range. Find people in the Nearby tab.',
            ),
            _Entry(
              leading: _LineBadge(MeshLink.relayed),
              title: 'Via mesh relay',
              body: 'No direct link, so other phones running Chatter pass the message along, hop by hop. '
                  'Slower, but it reaches people out of your range.',
            ),
          ]),
          const _Section(
            title: 'Trust badges',
            intro: 'Anyone can pick any handle, but nobody can fake a peer ID, so badges go by peer ID.',
          ),
          _Card(children: [
            _Entry(
              leading: _IconBadge(Icons.verified, color: chatter.verified),
              title: 'Verified contact',
              body: 'You checked their peer ID against their phone in person and marked them verified.',
            ),
            _Entry(
              leading: _IconBadge(Icons.warning_amber_rounded, color: chatter.warning),
              title: 'Impersonation warning',
              body: 'Another phone already goes by this handle, or one that looks like it. Check their peer ID '
                  'before trusting them.',
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String intro;
  const _Section({required this.title, required this.intro});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.primary)),
          ),
          const SizedBox(height: 4),
          Text(intro, style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: children),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  final Widget leading;
  final String title;
  final String body;
  const _Entry({required this.leading, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: leading),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(body, style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An icon on a soft disc, the size of a list avatar.
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  const _IconBadge(this.icon, {this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle),
      child: SizedBox.square(dimension: 40, child: Icon(icon, size: 22, color: color ?? cs.onSurface)),
    );
  }
}

/// A mesh map line on the same disc as [_IconBadge].
class _LineBadge extends StatelessWidget {
  final MeshLink link;
  const _LineBadge(this.link);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle),
      child: SizedBox.square(dimension: 40, child: Center(child: MeshLinkSample(link, width: 24))),
    );
  }
}
