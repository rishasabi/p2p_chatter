import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/link_preview_service.dart';
import 'message_text.dart';

/// A link from a message, under its text: the site it really goes to, up
/// front, and the page's title, description and picture once fetched. With
/// no internet it stays a plain card naming the site, so it never waits on
/// the network to draw. Tapping asks before opening.
class LinkPreviewCard extends StatefulWidget {
  final WebLink link;

  /// The bubble's text colour; the card is drawn in tints of it.
  final Color foreground;

  const LinkPreviewCard({super.key, required this.link, required this.foreground});

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  final _service = LinkPreviewService();
  LinkPreview? _preview;
  Uint8List? _image;
  LinkPreviewFailure? _failure;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LinkPreviewCard old) {
    super.didUpdateWidget(old);
    if (old.link.url != widget.link.url) _load();
  }

  void _load() {
    final url = widget.link.url;
    _preview = _service.cached(url);
    _image = _preview == null ? null : _service.cachedImage(_preview!);
    _failure = null;
    _loading = true;
    _service.preview(url).then((preview) async {
      if (!mounted || widget.link.url != url) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
      final image = await _service.image(preview);
      if (mounted && widget.link.url == url && image != null) setState(() => _image = image);
    }, onError: (Object e) {
      if (!mounted || widget.link.url != url) return;
      setState(() {
        _failure = e is LinkPreviewFailure ? e : LinkPreviewFailure.offline;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = widget.foreground;
    final muted = fg.withValues(alpha: 0.78);
    final link = widget.link;
    final preview = _preview;
    final secure = link.url.scheme == 'https';
    final claimed = link.claimedHost;
    final redirect = preview?.redirectHost;

    // Shown when there's no title: what kind of card this is, and why
    final (IconData tagIcon, String tag) = switch (_failure) {
      _ when _loading && preview == null => (Icons.downloading, 'Loading preview…'),
      LinkPreviewFailure.offline when preview == null => (Icons.cloud_off_outlined, 'Offline preview unavailable'),
      _ => (Icons.link, 'Web link'),
    };

    Widget warning(String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(text, style: theme.textTheme.bodySmall!.copyWith(color: fg, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The real destination comes first and boldest: link text, titles
        // and pictures are all up to whoever made the page or the message
        Row(
          children: [
            Icon(secure ? Icons.lock_outline : Icons.lock_open_outlined, size: 15, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                link.host,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge!.copyWith(color: fg),
              ),
            ),
          ],
        ),
        if (claimed != null) warning('The link says $claimed but goes to ${link.host}'),
        if (link.unusualHost) warning('Unusual characters in this address: it may imitate another site'),
        if (redirect != null) warning('Redirects to $redirect'),
        if (preview?.title != null) ...[
          const SizedBox(height: 4),
          Text(
            preview!.title!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium!.copyWith(color: fg, fontWeight: FontWeight.w700),
          ),
        ],
        if (preview?.description != null) ...[
          const SizedBox(height: 2),
          Text(
            preview!.description!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall!.copyWith(color: muted),
          ),
        ],
        if (preview?.title == null) ...[
          if (link.pathSummary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              link.pathSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(color: muted, fontFamily: 'monospace'),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tagIcon, size: 14, color: muted),
              const SizedBox(width: 4),
              Flexible(child: Text(tag, style: theme.textTheme.labelSmall!.copyWith(color: muted))),
            ],
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      label: 'Link to ${link.host}${preview?.title != null ? ', ${preview!.title}' : ''}',
      child: Material(
        color: fg.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: fg.withValues(alpha: 0.24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openLinkWithConsent(context, link.url.toString(), text: link.text),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _image == null
                ? details
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _image!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(child: details),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
