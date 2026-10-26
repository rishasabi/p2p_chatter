import 'package:flutter/material.dart';
import '../application_api.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

/// Asks for a channel to join or create (the same thing on a mesh: a channel
/// exists wherever people post to it), optionally private with a passphrase,
/// then opens it.
Future<void> showJoinChannelDialog(BuildContext context) async {
  final conversation = await showDialog<String>(context: context, builder: (_) => const _JoinChannelDialog());
  if (conversation == null || !context.mounted) return;
  final channel = ApplicationAPI().channelStatus(conversation);
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChatScreen(peerName: channel?['name'] as String? ?? '', peerId: conversation),
  ));
}

class _JoinChannelDialog extends StatefulWidget {
  const _JoinChannelDialog();

  @override
  State<_JoinChannelDialog> createState() => _JoinChannelDialogState();
}

class _JoinChannelDialogState extends State<_JoinChannelDialog> {
  final _name = TextEditingController();
  final _passphrase = TextEditingController();
  bool _private = false;
  bool _showPassphrase = false;
  bool _joining = false;
  String? _nameError;
  String? _passphraseError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final name = _name.text.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase();
    setState(() {
      _nameError = ApplicationAPI.validateChannelName(name);
      _passphraseError = _private && _passphrase.text.length < 8 ? 'Use at least 8 characters' : null;
      _error = null;
    });
    if (_nameError != null || _passphraseError != null) return;

    setState(() => _joining = true);
    try {
      final channel = await ApplicationAPI().joinChannel(name, passphrase: _private ? _passphrase.text : null);
      if (mounted) Navigator.of(context).pop(channel['id'] as String);
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = 'Couldn\'t join. ${e is ApiException ? e.message : e is ArgumentError ? e.message : e}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      title: const Text('Join or create a channel'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Everyone who joins the same name sees the same posts, passed from phone to phone.',
            style: theme.textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_joining,
            textInputAction: _private ? TextInputAction.next : TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Channel name',
              hintText: 'food-shelter',
              prefixText: '#',
              errorText: _nameError,
              helperText: 'Lowercase letters, numbers and dashes',
            ),
            onSubmitted: (_) => _private ? null : _join(),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private'),
            subtitle: const Text('Only people with the passphrase can read it'),
            value: _private,
            onChanged: _joining ? null : (v) => setState(() => _private = v),
          ),
          if (_private) ...[
            TextField(
              controller: _passphrase,
              enabled: !_joining,
              obscureText: !_showPassphrase,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                errorText: _passphraseError,
                helperText: 'Share it in person. A different passphrase is a different channel.',
                helperMaxLines: 3,
                suffixIcon: IconButton(
                  icon: Icon(_showPassphrase ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  tooltip: _showPassphrase ? 'Hide passphrase' : 'Show passphrase',
                  onPressed: () => setState(() => _showPassphrase = !_showPassphrase),
                ),
              ),
              onSubmitted: (_) => _join(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: theme.textTheme.bodyMedium!.copyWith(color: cs.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _joining ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _joining ? null : _join,
          child: _joining
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Join'),
        ),
      ],
    );
  }
}
