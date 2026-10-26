import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_store.dart';
import 'settings_store.dart';

/// A web link found in a message: where it really goes, and the words it was
/// written as when it's a Markdown link, which may claim somewhere else.
@immutable
class WebLink {
  final Uri url;
  final String? text;
  const WebLink(this.url, {this.text});

  String get host => url.host;

  /// The domain the link's words name when it isn't where it goes, e.g.
  /// `[redcross.org](https://evil.example)` gives 'redcross.org'.
  String? get claimedHost => claimedHostMismatch(text, url);

  /// The address uses look-alike or encoded characters ('xn--' punycode,
  /// percent-escapes), a common way to imitate a well-known site.
  bool get unusualHost => isUnusualHost(url.host);

  /// The path and query, shortened, for when there's no title to show.
  String get pathSummary {
    var path = url.path == '/' ? '' : url.path;
    if (url.hasQuery) path += '?…';
    return path.length > 48 ? '${path.substring(0, 47)}…' : path;
  }
}

final _markdownLink = RegExp(r'\[([^\]]*)\]\(\s*<?((?:https?://|www\.)[^)\s>]+)>?(?:\s+"[^"]*")?\s*\)', caseSensitive: false);
final _bareLink = RegExp(r'(?:https?://|www\.)[^\s<>()\[\]]+(?:\([^\s<>()]*\)[^\s<>()\[\]]*)*', caseSensitive: false);

/// The first http(s) link in [content], from a Markdown link or written out,
/// or null if there's none.
WebLink? firstWebLink(String content) {
  final md = _markdownLink.firstMatch(content);
  final bare = _bareLink.firstMatch(content);
  final String raw;
  String? text;
  if (md != null && (bare == null || md.start <= bare.start)) {
    raw = md.group(2)!;
    text = md.group(1);
  } else if (bare != null) {
    // Sentence punctuation after a link isn't part of it
    raw = bare.group(0)!.replaceFirst(RegExp(r'''[.,;:!?'"*_~]+$'''), '');
  } else {
    return null;
  }
  final url = Uri.tryParse(raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw);
  if (url == null || (url.scheme != 'http' && url.scheme != 'https') || !url.host.contains('.')) return null;
  return WebLink(url, text: text);
}

/// See [WebLink.unusualHost].
bool isUnusualHost(String host) =>
    host.split('.').any((label) => label.startsWith('xn--')) || host.contains('%') || RegExp(r'[^\x00-\x7F]').hasMatch(host);

/// See [WebLink.claimedHost].
String? claimedHostMismatch(String? text, Uri url) {
  if (text == null) return null;
  final claimed = text.trim().toLowerCase().replaceFirst(RegExp(r'^[a-z]+://'), '').split(RegExp(r'[/?#\s]')).first;
  // Only words that look like a domain name make a claim
  if (!RegExp(r'^([a-z0-9-]+\.)+[a-z]{2,}$').hasMatch(claimed)) return null;
  String bare(String host) => host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final real = bare(url.host);
  final named = bare(claimed);
  return real == named || real.endsWith('.$named') ? null : named;
}

/// What a link's page says about itself (OpenGraph or Twitter Card tags,
/// else its title), saved so it still shows once the internet is gone.
@immutable
class LinkPreview {
  final String? title;
  final String? description;
  final String? siteName;
  final Uri? image;

  /// Where redirects ended up, when that's a different site.
  final String? redirectHost;
  final DateTime fetchedAt;

  const LinkPreview({
    this.title,
    this.description,
    this.siteName,
    this.image,
    this.redirectHost,
    required this.fetchedAt,
  });

  bool get isEmpty => title == null && description == null;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (siteName != null) 'siteName': siteName,
        if (image != null) 'image': image.toString(),
        if (redirectHost != null) 'redirectHost': redirectHost,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
      };

  static LinkPreview? fromJson(Object? json) {
    if (json is! Map) return null;
    String? str(String key) => json[key] is String ? json[key] as String : null;
    final at = DateTime.tryParse(str('fetchedAt') ?? '');
    if (at == null) return null;
    final image = str('image');
    return LinkPreview(
      title: str('title'),
      description: str('description'),
      siteName: str('siteName'),
      image: image == null ? null : Uri.tryParse(image),
      redirectHost: str('redirectHost'),
      fetchedAt: at,
    );
  }
}

/// Why a link has no preview.
enum LinkPreviewFailure {
  /// Turned off in Settings.
  disabled,

  /// No internet, or the site didn't answer within [LinkPreviewService.timeout].
  offline,

  /// Fetched, but the page has nothing to show; or it's a local address
  /// Chatter won't fetch from.
  none,
}

/// Fetches link previews in the background, never for more than
/// [timeout] at a step, and keeps them in link_previews.json.
///
/// It refuses to fetch anything on this phone or its local network (the
/// node's own API, routers, other phones): a link in a message is chosen by
/// whoever sent it, and fetching it would otherwise let them reach those.
class LinkPreviewService {
  static final LinkPreviewService _instance = LinkPreviewService._();
  factory LinkPreviewService() => _instance;
  LinkPreviewService._();

  /// Never touches the network: links show as offline unless a test sets
  /// [debugClient] and [debugLookup].
  static bool isTestMode = false;
  @visibleForTesting
  static http.Client? debugClient;
  @visibleForTesting
  static Future<List<InternetAddress>> Function(String host)? debugLookup;

  static const timeout = Duration(seconds: 5);
  static const _file = 'link_previews.json';
  static const _maxCached = 200;
  static const _maxRedirects = 4;
  static const _maxPageBytes = 256 * 1024;
  static const _maxImageBytes = 300 * 1024;
  static const _staleAfter = Duration(days: 7);
  static const _retryAfter = Duration(minutes: 2);

  final LinkedHashMap<String, LinkPreview> _cache = LinkedHashMap();
  final Map<String, Future<LinkPreview>> _inFlight = {};
  final Map<String, (LinkPreviewFailure, DateTime)> _failed = {};
  final LinkedHashMap<String, Uint8List?> _images = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _imagesInFlight = {};
  Future<void>? _loading;
  bool _loaded = false;

  bool get enabled => SettingsStore().getBool(SettingsStore.linkPreviews, fallback: true);

  /// The preview saved for [url], however old, without fetching anything.
  LinkPreview? cached(Uri url) => _cache[url.toString()];

  /// The image already downloaded for [preview], if any.
  Uint8List? cachedImage(LinkPreview preview) => preview.image == null ? null : _images[preview.image.toString()];

  /// The preview for [url]: saved, or fetched now. Throws a
  /// [LinkPreviewFailure] when there's none to show.
  Future<LinkPreview> preview(Uri url) async {
    if (!enabled) throw LinkPreviewFailure.disabled;
    if (!_loaded) await (_loading ??= _load());
    final key = url.toString();
    final saved = _cache[key];
    if (saved != null && DateTime.now().difference(saved.fetchedAt) < _staleAfter) return saved;
    final failed = _failed[key];
    // A page with nothing to show won't have something a minute later
    final wait = failed?.$1 == LinkPreviewFailure.none ? const Duration(days: 1) : _retryAfter;
    if (failed != null && DateTime.now().difference(failed.$2) < wait) {
      if (saved != null) return saved;
      throw failed.$1;
    }
    return _inFlight[key] ??= _fetch(url).then((preview) {
      _remember(key, preview);
      return preview;
    }, onError: (Object e) {
      final failure = e is LinkPreviewFailure ? e : LinkPreviewFailure.offline;
      _failed[key] = (failure, DateTime.now());
      // An old preview beats none
      if (saved != null) return saved;
      throw failure;
    }).whenComplete(() {
      // Not `=> remove(key)`: returning this very future would make it wait on itself
      _inFlight.remove(key);
    });
  }

  /// The picture [preview] names, downloaded once per run (kept in memory
  /// only); null if there isn't one or it couldn't be fetched.
  Future<Uint8List?> image(LinkPreview preview) {
    final url = preview.image;
    if (url == null || !enabled) return Future.value();
    final key = url.toString();
    if (_images.containsKey(key)) return Future.value(_images[key]);
    return _imagesInFlight[key] ??= _fetchImage(url).catchError((Object _) => null).then((bytes) {
      _images[key] = bytes;
      while (_images.length > 40) {
        _images.remove(_images.keys.first);
      }
      return bytes;
    }).whenComplete(() {
      _imagesInFlight.remove(key);
    });
  }

  Future<void> _load() async {
    final stored = await LocalStore.read(_file);
    stored.forEach((url, json) {
      final preview = LinkPreview.fromJson(json);
      if (preview != null) _cache[url] = preview;
    });
    _loaded = true;
  }

  void _remember(String key, LinkPreview preview) {
    _failed.remove(key);
    _cache.remove(key); // re-inserted as the newest
    _cache[key] = preview;
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
    LocalStore.write(_file, {for (final e in _cache.entries) e.key: e.value.toJson()});
  }

  http.Client _client() => debugClient ?? http.Client();

  Future<List<InternetAddress>> _lookup(String host) =>
      (debugLookup ?? InternetAddress.lookup)(host).timeout(timeout);

  /// Whether [url] is out on the internet, not on this phone or its network.
  Future<bool> _isPublic(Uri url) async {
    if (url.scheme != 'http' && url.scheme != 'https') return false;
    // Only the standard ports: anything else is more likely a local service
    if (url.hasPort && url.port != 80 && url.port != 443) return false;
    final host = url.host.toLowerCase();
    if (host.isEmpty || host == 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return false;
    final literal = InternetAddress.tryParse(host);
    final addresses = literal != null ? [literal] : await _lookup(host);
    return addresses.isNotEmpty && addresses.every(isPublicAddress);
  }

  Future<LinkPreview> _fetch(Uri url) async {
    if (isTestMode && debugClient == null) throw LinkPreviewFailure.offline;
    final client = _client();
    try {
      var target = url;
      for (var hop = 0; hop <= _maxRedirects; hop++) {
        if (!await _isPublic(target)) throw LinkPreviewFailure.none;
        final request = http.Request('GET', target)
          ..followRedirects = false // each hop is checked above first
          ..headers['Accept'] = 'text/html,application/xhtml+xml'
          ..headers['User-Agent'] = 'Mozilla/5.0 (compatible; ChatterLinkPreview/1.0)';
        final response = await client.send(request).timeout(timeout);
        final location = response.headers['location'];
        if (response.statusCode >= 300 && response.statusCode < 400 && location != null) {
          unawaited(response.stream.drain<void>().catchError((_) {}));
          target = target.resolve(location);
          continue;
        }
        if (response.statusCode != 200 || !(response.headers['content-type'] ?? '').contains('html')) {
          unawaited(response.stream.drain<void>().catchError((_) {}));
          throw LinkPreviewFailure.none;
        }
        final html = utf8.decode(await _read(response.stream, _maxPageBytes), allowMalformed: true);
        final preview = parseLinkPreview(html, target, redirectHost: target.host != url.host ? target.host : null);
        if (preview.isEmpty) throw LinkPreviewFailure.none;
        return preview;
      }
      throw LinkPreviewFailure.none; // too many redirects
    } on LinkPreviewFailure {
      rethrow;
    } catch (_) {
      throw LinkPreviewFailure.offline; // no route, DNS failure, timeout, reset
    } finally {
      if (debugClient == null) client.close();
    }
  }

  Future<Uint8List?> _fetchImage(Uri url) async {
    if (isTestMode && debugClient == null) return null;
    if (!await _isPublic(url)) return null;
    final client = _client();
    try {
      final response = await client.send(http.Request('GET', url)..followRedirects = false).timeout(timeout);
      final type = response.headers['content-type'] ?? '';
      // SVG can't be drawn by Image, and is a script-capable format anyway
      if (response.statusCode != 200 || !type.startsWith('image/') || type.contains('svg')) {
        unawaited(response.stream.drain<void>().catchError((_) {}));
        return null;
      }
      final bytes = await _read(response.stream, _maxImageBytes);
      return bytes.length >= _maxImageBytes ? null : bytes;
    } finally {
      if (debugClient == null) client.close();
    }
  }

  /// Up to [limit] bytes of [stream], with no more than [timeout] between
  /// chunks.
  static Future<Uint8List> _read(Stream<List<int>> stream, int limit) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in stream.timeout(timeout)) {
      out.add(chunk);
      if (out.length >= limit) break; // a page's head is near the top
    }
    return out.takeBytes();
  }
}

/// Whether [address] is on the public internet: not loopback, private
/// (10/8, 172.16/12, 192.168/16, fc00::/7), carrier-grade NAT, link-local,
/// multicast or unspecified.
bool isPublicAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) return false;
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return !(b[0] == 0 ||
        b[0] == 10 ||
        (b[0] == 100 && b[1] >= 64 && b[1] < 128) ||
        (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
        (b[0] == 192 && b[1] == 168) ||
        b[0] >= 240);
  }
  if (b.every((x) => x == 0)) return false; // ::
  if ((b[0] & 0xFE) == 0xFC) return false; // unique local
  // IPv4-mapped (::ffff:a.b.c.d): judge the IPv4 address
  if (b.sublist(0, 10).every((x) => x == 0) && b[10] == 0xFF && b[11] == 0xFF) {
    return isPublicAddress(InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))));
  }
  return true;
}

final _metaTag = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
final _linkTag = RegExp(r'<link\b[^>]*>', caseSensitive: false);
final _attribute = RegExp(r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''');
final _titleTag = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false);

/// Reads OpenGraph and Twitter Card tags (else `<title>`, the meta
/// description and the page icon) from a page fetched from [base].
LinkPreview parseLinkPreview(String html, Uri base, {String? redirectHost}) {
  final meta = <String, String>{};
  Map<String, String> attributes(String tag) => {
        for (final m in _attribute.allMatches(tag)) m.group(1)!.toLowerCase(): m.group(2) ?? m.group(3) ?? m.group(4) ?? '',
      };
  for (final tag in _metaTag.allMatches(html)) {
    final attrs = attributes(tag.group(0)!);
    final key = (attrs['property'] ?? attrs['name'])?.toLowerCase();
    final content = attrs['content'];
    if (key != null && content != null && content.trim().isNotEmpty) meta.putIfAbsent(key, () => content);
  }
  String? icon;
  for (final tag in _linkTag.allMatches(html)) {
    final attrs = attributes(tag.group(0)!);
    final rel = attrs['rel']?.toLowerCase() ?? '';
    if (attrs['href'] != null && (rel == 'icon' || rel == 'shortcut icon' || rel == 'apple-touch-icon')) {
      // The touch icon is the larger one; otherwise the first icon listed
      if (icon == null || rel == 'apple-touch-icon') icon = attrs['href'];
    }
  }

  String? text(List<String> keys, int max) {
    for (final key in keys) {
      final value = meta[key];
      if (value != null) return _clean(value, max);
    }
    return null;
  }

  final title = text(['og:title', 'twitter:title'], 200) ??
      (_titleTag.firstMatch(html) == null ? null : _clean(_titleTag.firstMatch(html)!.group(1)!, 200));
  final imageRef = meta['og:image:secure_url'] ?? meta['og:image'] ?? meta['twitter:image'] ?? meta['twitter:image:src'] ?? icon;
  final image = imageRef == null ? null : Uri.tryParse(_decodeEntities(imageRef.trim()));
  return LinkPreview(
    title: title == null || title.isEmpty ? null : title,
    description: text(['og:description', 'twitter:description', 'description'], 300),
    siteName: text(['og:site_name'], 80),
    image: image == null ? null : base.resolveUri(image),
    redirectHost: redirectHost,
    fetchedAt: DateTime.now(),
  );
}

String _clean(String value, int max) {
  final text = _decodeEntities(value).replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > max ? '${text.substring(0, max - 1)}…' : text;
}

String _decodeEntities(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        final code = int.tryParse(e.substring(2), radix: 16);
        return code == null || code > 0x10FFFF ? m.group(0)! : String.fromCharCode(code);
      }
      if (e.startsWith('#')) {
        final code = int.tryParse(e.substring(1));
        return code == null || code > 0x10FFFF ? m.group(0)! : String.fromCharCode(code);
      }
      return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'mdash': '—', 'ndash': '–', 'hellip': '…'}[e] ??
          m.group(0)!;
    });
