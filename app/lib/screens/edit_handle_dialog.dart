import 'package:flutter/material.dart';
import '../application_api.dart';
import '../theme/app_theme.dart';

/// Asks for a new handle and, once saved, shares it with everyone nearby.
/// Returns the new handle, or null if nothing changed.
Future<String?> showEditHandleDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const EditHandleDialog());

class EditHandleDialog extends StatefulWidget {
  const EditHandleDialog({super.key});

  @override
  State<EditHandleDialog> createState() => _EditHandleDialogState();
}

class _EditHandleDialogState extends State<EditHandleDialog> {
  final _api = ApplicationAPI();
  late final _handle = TextEditingController(text: _api.myHandle ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  String get _text => _handle.text.trim();
  String? get _problem => ApplicationAPI.validateHandle(_text);
  bool get _unchanged => _text == _api.myHandle;

  /// A known peer already going by this handle, or one that looks like it.
  String? get _takenBy => _problem == null && !_unchanged ? _api.peerUsingHandle(_text) : null;

  Future<void> _save() async {
    if (_problem != null || _unchanged) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Saved to profile.json and pushed out over Wi-Fi and Bluetooth
      await _api.setMyHandle(_text);
      if (mounted) Navigator.of(context).pop(_text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn\'t change your handle. ${e is ArgumentError ? e.message : 'Is your node running?'}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final takenBy = _takenBy;

    return AlertDialog(
      title: const Text('Change your handle'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nearby phones see the new name straight away. Your peer ID stays the same, '
            'so people who verified you still can.',
            style: theme.textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _handle,
            autofocus: true,
            enabled: !_saving,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: ApplicationAPI.maxHandleLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Handle',
              prefixText: '@ ',
              helperText: 'Letters, numbers, dots, dashes or underscores',
              helperMaxLines: 2,
              errorMaxLines: 3,
              errorText: _handle.text.isEmpty ? null : _problem,
            ),
            onChanged: (_) => setState(() => _error = null),
            // A clash has to be confirmed with the button, never by Enter
            onSubmitted: (_) => takenBy == null ? _save() : null,
          ),
          if (takenBy != null) ...[
            const SizedBox(height: 12),
            HandleCollisionWarning(handle: _text, peerId: takenBy),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: theme.textTheme.bodyMedium!.copyWith(color: cs.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || _problem != null || _unchanged ? null : _save,
          child: _saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(takenBy != null ? 'Confirm & Use Handle' : 'Save'),
        ),
      ],
    );
  }
}

/// The amber card shown when a handle someone wants is already another
/// known peer's.
class HandleCollisionWarning extends StatelessWidget {
  final String handle;
  final String peerId;

  const HandleCollisionWarning({super.key, required this.handle, required this.peerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatter = ChatterColors.of(context);
    final fg = chatter.onWarningContainer;
    final tail = peerId.length > 4 ? peerId.substring(peerId.length - 4) : peerId;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: chatter.warningContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: chatter.warning),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Caution: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                    text: 'Another device on this network (#$tail) is already using the handle @$handle. '
                        'Choosing a duplicate handle may cause confusion or impersonation flags. '
                        'Do you still wish to continue?',
                  ),
                ]),
                style: theme.textTheme.bodyMedium!.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
