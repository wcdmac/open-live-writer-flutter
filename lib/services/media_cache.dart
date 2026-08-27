import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Disk cache for images referenced by post content. Downloaded once
/// while online, reused by the visual editor and preview while offline —
/// an offline copy of a post then opens with working images.
class MediaCache {
  MediaCache._();

  static final MediaCache instance = MediaCache._();

  /// A failed URL is quarantined only for this long — a momentary network
  /// hiccup must not blacklist an image until app restart.
  static const _failureTtl = Duration(minutes: 5);

  /// Rough ceiling for the whole cache; the oldest files are evicted when
  /// exceeded so offline copies can't grow the disk usage without bound.
  static const _maxCacheBytes = 200 * 1024 * 1024;

  Directory? _base;
  final Set<String> _downloading = {};
  final Map<String, DateTime> _failedAt = {};

  Future<Directory> _baseDir() async {
    if (_base != null) return _base!;
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}media_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _base = dir;
    return dir;
  }

  /// Stable file name for a URL: a hash prefix (short) plus a readable
  /// tail of the URL path so cached files stay identifiable.
  ///
  /// FNV-1a instead of String.hashCode: Dart makes no cross-platform
  /// stability guarantee for hashCode, and an unstable name silently
  /// orphans previously cached files.
  String _fileNameFor(String url) {
    var hash = 0x811c9dc5;
    for (final byte in url.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final hashHex = hash.toRadixString(16);
    final tail = url.split('/').lastOrNull ?? '';
    final safe = tail.split('?').first.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    return '$hashHex-${safe.length > 48 ? safe.substring(safe.length - 48) : safe}';
  }

  /// Returns the cached file for [url], or null when not (yet) cached.
  /// Purely local — never touches the network.
  Future<File?> existingFile(String url) async {
    if (!url.startsWith('http')) return null;
    try {
      final dir = await _baseDir();
      final file = File('${dir.path}${Platform.pathSeparator}'
          '${_fileNameFor(url)}');
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads [url] into the cache if missing; returns the file, or
  /// null on failure. Failures are remembered for [_failureTtl] so a dead
  /// URL is not retried on every build, but a transient network error
  /// heals itself after the TTL instead of blacklisting until restart.
  Future<File?> fetch(String url) async {
    final failedAt = _failedAt[url];
    final quarantined = failedAt != null &&
        DateTime.now().difference(failedAt) < _failureTtl;
    if (!url.startsWith('http') || quarantined || _downloading.contains(url)) {
      return existingFile(url);
    }
    _failedAt.remove(url);
    _downloading.add(url);
    try {
      final dir = await _baseDir();
      final file = File('${dir.path}${Platform.pathSeparator}'
          '${_fileNameFor(url)}');
      if (!await file.exists()) {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
          debugPrint('MediaCache: ${res.statusCode} for $url');
          _failedAt[url] = DateTime.now();
          return null;
        }
        await file.writeAsBytes(res.bodyBytes, flush: true);
        unawaited(_evictIfNeeded());
      }
      return file;
    } catch (_) {
      _failedAt[url] = DateTime.now();
      return null;
    } finally {
      _downloading.remove(url);
    }
  }

  /// Enforces [_maxCacheBytes] by deleting the least recently written
  /// files first. Best effort: IO errors are ignored.
  Future<void> _evictIfNeeded() async {
    try {
      final dir = await _baseDir();
      final files = <File>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          files.add(entity);
          total += await entity.length();
        }
      }
      if (total <= _maxCacheBytes) return;
      final stamped = <(File, DateTime)>[];
      for (final f in files) {
        try {
          stamped.add((f, await f.lastModified()));
        } catch (_) {
          stamped.add((f, DateTime.now()));
        }
      }
      stamped.sort((a, b) => a.$2.compareTo(b.$2));
      for (final (file, _) in stamped) {
        if (total <= _maxCacheBytes) break;
        final len = await file.length();
        await file.delete();
        total -= len;
      }
    } catch (_) {
      // Eviction is best effort.
    }
  }

  /// Fire-and-forget prefetch of every remote <img> in [html]. Called as
  /// content streams through the editor/preview while online, so the
  /// cache quietly fills up for offline sessions.
  Future<void> prefetchImages(String html) async {
    final urls = RegExp(r'<img[^>]+src="(https?://[^"]+)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toSet();
    for (final url in urls) {
      unawaited(fetch(url));
    }
  }
}

/// Image widget that prefers the disk cache over the network: while
/// offline (or when the URL is unreachable) a previously cached copy
/// still renders. Kicks off a background download when not cached yet.
class CachedImage extends StatefulWidget {
  const CachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget Function(
      BuildContext context, Widget child, ImageChunkEvent? progress)?
      loadingBuilder;
  final Widget? Function(BuildContext context)? errorBuilder;

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  File? _local;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _local = null;
      _load();
    }
  }

  Future<void> _load() async {
    final file = await MediaCache.instance.existingFile(widget.url);
    if (file != null && mounted && file.path != _local?.path) {
      setState(() => _local = file);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget? fallback =
        widget.errorBuilder != null ? widget.errorBuilder!(context) : null;
    Widget imgError(BuildContext _, Object _, StackTrace? _) =>
        fallback ?? const SizedBox.shrink();
    if (_local != null) {
      return Image.file(
        _local!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: imgError,
      );
    }
    // Not cached yet: show the network image and warm the cache in the
    // background for the next (possibly offline) render.
    unawaited(MediaCache.instance.fetch(widget.url));
    return Image.network(
      widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: imgError,
    );
  }
}
