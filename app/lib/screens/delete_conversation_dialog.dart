import 'package:flutter/material.dart';
import '../application_api.dart';
import '../widgets/feedback.dart';

/// A menu entry for something that destroys data: in the error colour, with
/// its icon, so it never relies on colour alone.
class DangerMenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const DangerMenuLabel(this.icon, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Flexible(child: Text(label, style: TextStyle(color: color))),
      ],
    );
  }
}

/// Asks before deleting a conversation, or leaving and deleting a channel,
/// then does it. Returns whether it was deleted.
Future<bool> confirmDeleteConversation(BuildContext context, String conversationId) async {
  final api = ApplicationAPI();
  final channel = api.channelStatus(conversationId);
  final cs = Theme.of(context).colorScheme;

  final String title, body, action;
  if (channel != null) {
    final name = '#${channel['name']}';
    title = 'Leave and delete $name?';
    body = 'You\'ll stop receiving its posts, and all of its messages will be permanently removed from your '
        'device\'s local storage. This action cannot be undone.'
        '${channel['private'] == true ? ' To come back you\'ll need its passphrase again.' : ''}';
    action = 'Leave & delete';
  } else {
    final handle = api.handleOf(conversationId);
    final who = api.aliasOf(conversationId) ?? (handle != null ? '@$handle' : api.displayName(conversationId));
    title = 'Delete chat?';
    body = 'Delete conversation with $who? This will permanently remove all messages from your device\'s local '
        'storage. This action cannot be undone.';
    action = 'Delete';
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.delete_forever_outlined, color: cs.error),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  await api.deleteConversation(conversationId);
  if (context.mounted) {
    showNotice(context, channel != null ? 'Left and deleted #${channel['name']}' : 'Chat deleted',
        tone: NoticeTone.success, duration: const Duration(seconds: 2));
  }
  return true;
}
