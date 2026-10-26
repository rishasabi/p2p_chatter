import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/custom_theme.dart';
import '../widgets/feedback.dart';

/// Pick a colour for each part of the app, watch a sample chat change as you
/// go, and pass the result to the rest of your team as a `.chattertheme` file
/// or as JSON pasted into a message.
class ThemeEditorScreen extends ConsumerStatefulWidget {
  const ThemeEditorScreen({super.key});

  @override
  ConsumerState<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends ConsumerState<ThemeEditorScreen> {
  /// Theme files are a few hundred bytes; anything this big isn't one.
  static const _maxFileBytes = 64 * 1024;

  late CustomThemeConfig _draft;

  /// What [_draft] started as, or was last applied as: leaving with anything
  /// else asks first.
  late CustomThemeConfig _baseline;
  final _name = TextEditingController();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // The saved palette, else Chatter's own look in whichever brightness is showing
    _draft = ref.read(customThemeProvider).config ??
        (Theme.of(context).brightness == Brightness.dark
            ? CustomThemeConfig.lanternNight
            : CustomThemeConfig.lanternDawn);
    _baseline = _draft;
    _name.text = _draft.name;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _use(CustomThemeConfig config, {bool keepName = false}) => setState(() {
        _draft = keepName ? config.withName(_name.text) : config;
        if (!keepName) _name.text = config.name;
      });

  void _apply() {
    ref.read(customThemeProvider.notifier).apply(_draft);
    setState(() => _baseline = _draft);
    showNotice(context, '"${_draft.name}" is on', tone: NoticeTone.success, duration: const Duration(seconds: 2));
  }

  /// An imported theme goes on straight away: that's why it was shared.
  void _applyImported(CustomThemeConfig config) {
    _use(config);
    _apply();
  }

  Future<void> _pickColor(ThemeColorRole role) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(title: role.label, initial: _draft[role]),
    );
    if (color != null) setState(() => _draft = _draft.withColor(role, color));
  }

  // ── Import ──────────────────────────────────────────────────────────────────

  Future<void> _showImport() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Paste theme JSON'),
              subtitle: const Text('From a message or a note'),
              onTap: () => Navigator.pop(context, 'paste'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Open a .${CustomThemeConfig.fileExtension} file'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'paste') {
      final config = await showDialog<CustomThemeConfig>(context: context, builder: (_) => const _PasteThemeDialog());
      if (config != null && mounted) _applyImported(config);
    } else if (choice == 'file') {
      await _importFile();
    }
  }

  Future<void> _importFile() async {
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Open a Chatter theme');
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxFileBytes) throw const FormatException('That file is too big to be a Chatter theme.');
      final config = CustomThemeConfig.decode(utf8.decode(bytes, allowMalformed: true));
      if (mounted) _applyImported(config);
    } on FormatException catch (e) {
      if (mounted) showNotice(context, e.message, tone: NoticeTone.error);
    } catch (e) {
      if (mounted) showNotice(context, 'Couldn\'t open the file: $e', tone: NoticeTone.error);
    }
  }

  // ── Export ──────────────────────────────────────────────────────────────────

  Future<void> _showExport() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy theme JSON'),
              subtitle: const Text('Paste it into a chat to share it over the mesh'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save as a .${CustomThemeConfig.fileExtension} file'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: _draft.encode()));
      if (mounted) showNotice(context, 'Theme copied', tone: NoticeTone.success, duration: const Duration(seconds: 2));
    } else if (choice == 'file') {
      await _exportFile();
    }
  }

  Future<void> _exportFile() async {
    final slug = _draft.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save theme',
        fileName: '${slug.isEmpty ? 'theme' : slug}.${CustomThemeConfig.fileExtension}',
        bytes: utf8.encode(_draft.encode()),
        mimeType: 'application/json',
      );
      if (saved != null && mounted) showNotice(context, 'Theme saved', tone: NoticeTone.success);
    } catch (e) {
      if (mounted) showNotice(context, 'Couldn\'t save the file: $e', tone: NoticeTone.error);
    }
  }

  // ── Layout ──────────────────────────────────────────────────────────────────

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your colours haven\'t been applied yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final custom = ref.watch(customThemeProvider);
    final applied = custom.enabled && custom.config == _draft;
    final problems = _draft.lowContrast();

    return PopScope(
      canPop: _draft == _baseline,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customize theme'),
          actions: [
            IconButton(icon: const Icon(Icons.file_download_outlined), tooltip: 'Import theme', onPressed: _showImport),
            IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Export theme', onPressed: _showExport),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Theme(data: AppTheme.custom(_draft), child: const ThemePreview()),
            for (final p in problems)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 20, color: ChatterColors.of(context).warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p.what} is hard to read: ${p.ratio.toStringAsFixed(1)}:1, aim for ${p.needed.toStringAsFixed(1)}:1.',
                        style: theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              maxLength: CustomThemeConfig.maxNameLength,
              decoration: const InputDecoration(labelText: 'Theme name'),
              onChanged: (name) => setState(() => _draft = _draft.withName(name)),
            ),
            const SizedBox(height: 8),
            _Heading('Start from'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in CustomThemeConfig.presets)
                  ActionChip(
                    avatar: _Swatch(preset[ThemeColorRole.surface], inner: preset[ThemeColorRole.myBubble]),
                    label: Text(preset.name),
                    onPressed: () => _use(preset),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _Heading('Colours'),
            for (final role in ThemeColorRole.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Swatch(_draft[role], size: 36),
                title: Text(role.label),
                subtitle: Text(colorToHex(_draft[role]), style: const TextStyle(fontFamily: 'monospace')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _pickColor(role),
              ),
            if (custom.enabled) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Back to the standard theme'),
                onPressed: () {
                  ref.read(customThemeProvider.notifier).turnOff();
                  showNotice(context, 'Custom theme off', duration: const Duration(seconds: 2));
                },
              ),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              icon: Icon(applied ? Icons.check : Icons.palette_outlined),
              label: Text(applied ? 'Applied' : 'Apply theme'),
              onPressed: applied ? null : _apply,
            ),
          ),
        ),
      ),
    );
  }
}

/// A slice of the app in the theme around it: the top bar, a peer who's in
/// reach, a bubble each way, a card, buttons and a switch.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chatter = ChatterColors.of(context);
    final bar = theme.appBarTheme;
    const bubbleRadius = BorderRadius.all(Radius.circular(18));

    Widget bubble(String text, Color bg, Color fg, {required bool mine}) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: bubbleRadius,
              border: !mine && theme.brightness == Brightness.light ? Border.all(color: cs.outlineVariant) : null,
            ),
            child: Text(text, style: theme.textTheme.bodyLarge!.copyWith(color: fg)),
          ),
        );

    return Semantics(
      label: 'Preview of the theme',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: bar.backgroundColor,
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(child: Text('Chats', style: bar.titleTextStyle)),
                    Icon(Icons.refresh, color: bar.foregroundColor),
                  ],
                ),
              ),
              Container(
                color: cs.surface,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.secondaryContainer,
                              border: Border.all(color: chatter.reach, width: 2.5),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text('medic_lead', style: theme.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600))),
                          Icon(Icons.wifi_tethering, size: 18, color: chatter.reach),
                          const SizedBox(width: 4),
                          Flexible(child: Text('In reach', style: theme.textTheme.bodySmall!.copyWith(color: chatter.reach))),
                        ],
                      ),
                    ),
                    bubble('Water at the school gym until 6pm', chatter.bubbleIn, chatter.onBubbleIn, mine: false),
                    bubble('On my way, 10 min', chatter.bubbleOut, chatter.onBubbleOut, mine: true),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton(onPressed: () {}, child: const Text('Join')),
                        OutlinedButton(onPressed: () {}, child: const Text('Later')),
                        Switch(value: true, onChanged: (_) {}),
                        IconButton.filled(
                          onPressed: () {},
                          tooltip: 'Send (preview)',
                          style: IconButton.styleFrom(backgroundColor: chatter.accent, foregroundColor: chatter.onAccent),
                          icon: const Icon(Icons.arrow_upward),
                        ),
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

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.primary)),
      ),
    );
  }
}

/// A colour sample; with [inner], a dot of a second colour on it.
class _Swatch extends StatelessWidget {
  final Color color;
  final Color? inner;
  final double size;
  const _Swatch(this.color, {this.inner, this.size = 24});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: inner == null
            ? null
            : Container(
                width: size * 0.45,
                height: size * 0.45,
                decoration: BoxDecoration(color: inner, shape: BoxShape.circle),
              ),
      );
}

/// Hue, saturation and brightness sliders, and a hex field for pasting an
/// exact colour.
class _ColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initial;
  const _ColorPickerDialog({required this.title, required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: colorToHex(widget.initial));
  bool _hexValid = true;

  Color get _color => _hsv.toColor();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _slide(HSVColor hsv) => setState(() {
        _hsv = hsv;
        _hex.text = colorToHex(_color);
        _hexValid = true;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget slider(String label, double value, double max, ValueChanged<double> onChanged) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(label, style: theme.textTheme.labelMedium),
            ),
            Slider(value: value, max: max, onChanged: onChanged, semanticFormatterCallback: (v) => '$label ${v.round()}'),
          ],
        );

    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Text(
              colorToHex(_color),
              style: theme.textTheme.labelLarge!.copyWith(color: readableOn(_color)),
            ),
          ),
          slider('Hue', _hsv.hue, 360, (v) => _slide(_hsv.withHue(v))),
          slider('Saturation', _hsv.saturation * 100, 100, (v) => _slide(_hsv.withSaturation(v / 100))),
          slider('Brightness', _hsv.value * 100, 100, (v) => _slide(_hsv.withValue(v / 100))),
          const SizedBox(height: 8),
          TextField(
            controller: _hex,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: 'Hex colour',
              hintText: '#E11D48',
              errorText: _hexValid ? null : 'Use six hex digits, like #E11D48',
            ),
            onChanged: (text) {
              final color = parseHexColor(text);
              setState(() {
                _hexValid = color != null;
                if (color != null) _hsv = HSVColor.fromColor(color);
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _hexValid ? () => Navigator.pop(context, _color) : null,
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}

/// Takes a theme as JSON, from whatever's on the clipboard to begin with.
class _PasteThemeDialog extends StatefulWidget {
  const _PasteThemeDialog();

  @override
  State<_PasteThemeDialog> createState() => _PasteThemeDialogState();
}

class _PasteThemeDialogState extends State<_PasteThemeDialog> {
  final _json = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final text = data?.text;
      if (mounted && _json.text.isEmpty && text != null && text.trimLeft().startsWith('{')) _json.text = text;
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  void _import() {
    try {
      Navigator.pop(context, CustomThemeConfig.decode(_json.text));
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Paste a theme'),
        scrollable: true,
        content: TextField(
          controller: _json,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: '{"name": "...", "version": 1, "colors": {...}}',
            errorText: _error,
            errorMaxLines: 4,
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _import, child: const Text('Import and apply')),
        ],
      );
}
