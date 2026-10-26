import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'feedback.dart';

/// Anything that could be Markdown: emphasis, code, headings, quotes, links,
/// tables, lists, or a bare URL. Everything else stays a plain Text, which is
/// cheaper to lay out in a long thread.
final _markdownHint = RegExp(r'[*_`#>~|\[]|^\s*([-+]|\d+[.)])\s|https?://|www\.', multiLine: true);

/// A message body: Markdown (GitHub flavour: bold, italics, lists and
/// checklists, quotes, code, tables, links) styled for the bubble it sits in.
/// Line breaks typed in the composer stay line breaks.
class MessageText extends StatelessWidget {
  final String content;

  /// Body text style, already coloured for the bubble.
  final TextStyle style;

  const MessageText(this.content, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    if (!_markdownHint.hasMatch(content)) return Text(content, style: style);

    final theme = Theme.of(context);
    final fg = style.color ?? theme.colorScheme.onSurface;
    final mono = style.copyWith(fontFamily: 'monospace', fontSize: (style.fontSize ?? 16) * 0.9);
    final tint = fg.withValues(alpha: 0.1);
    final textTheme = theme.textTheme;

    return MarkdownBody(
      data: content,
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, _) => openLinkWithConsent(context, href ?? text),
      // Nothing is fetched from the network: an image shows as its description
      imageBuilder: (uri, title, alt) => Text('[image: ${alt?.isNotEmpty == true ? alt : uri}]', style: style),
      // Code blocks wrap instead of scrolling sideways: a scroll view inside a
      // bubble that sizes to its text can't be measured
      builders: {'pre': _CodeBlockBuilder(mono)},
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: style,
        strong: const TextStyle(fontWeight: FontWeight.w700),
        em: const TextStyle(fontStyle: FontStyle.italic),
        del: const TextStyle(decoration: TextDecoration.lineThrough),
        // Underlined as well as coloured, so a link never depends on colour alone
        a: TextStyle(color: fg, decoration: TextDecoration.underline, decorationColor: fg, fontWeight: FontWeight.w600),
        h1: textTheme.titleLarge!.copyWith(color: fg),
        h2: textTheme.titleMedium!.copyWith(color: fg),
        h3: textTheme.titleSmall!.copyWith(color: fg),
        h4: style.copyWith(fontWeight: FontWeight.w700),
        h5: style.copyWith(fontWeight: FontWeight.w700),
        h6: style.copyWith(fontWeight: FontWeight.w700),
        listBullet: style,
        checkbox: style,
        blockquote: style,
        blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        blockquoteDecoration: BoxDecoration(
          color: tint,
          border: Border(left: BorderSide(color: fg.withValues(alpha: 0.55), width: 3)),
        ),
        code: mono.copyWith(backgroundColor: tint),
        codeblockDecoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(8)),
        codeblockPadding: const EdgeInsets.all(10),
        tableHead: style.copyWith(fontWeight: FontWeight.w700),
        tableBody: style,
        tableBorder: TableBorder.all(color: fg.withValues(alpha: 0.3)),
        tableColumnWidth: const FlexColumnWidth(),
        horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: fg.withValues(alpha: 0.4)))),
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final TextStyle style;
  _CodeBlockBuilder(this.style);

  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) => Padding(
        padding: const EdgeInsets.all(10),
        child: Text(text.text.replaceFirst(RegExp(r'\n$'), ''), style: style),
      );
}

/// [content] without Markdown punctuation, on one line, for previews and
/// notifications where it would show as clutter.
String markdownToPlain(String content) => content
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!) // links and images
    .replaceAll(RegExp(r'^\s{0,3}(#{1,6}|>|[-+*]\s+\[[ xX]\]|[-+*])\s+', multiLine: true), '')
    // Single underscores stay: handles like medic_triage use them
    .replaceAll(RegExp(r'(__|~~|`{1,3}|\*)'), '')
    .replaceAll(RegExp(r'\s*\n\s*'), ' ')
    .trim();

const _openableSchemes = {'http', 'https', 'mailto', 'tel', 'geo'};

/// Asks before following a link from a message: it leaves Chatter, needs a
/// connection, and could have been sent by anyone.
Future<void> openLinkWithConsent(BuildContext context, String link) async {
  final withScheme = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(link) ? link : 'https://$link';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !_openableSchemes.contains(uri.scheme.toLowerCase())) {
    showNotice(context, 'Chatter doesn\'t open this kind of link.', tone: NoticeTone.error);
    return;
  }

  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Open link?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(uri.toString(), style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 12),
          const Text('It opens outside Chatter and may need an internet connection. '
              'Only open links from people you trust.'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open')),
      ],
    ),
  );
  if (choice != true || !context.mounted) return;

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened && context.mounted) {
    showNotice(context, 'No app on this phone could open the link.', tone: NoticeTone.error);
  }
}
