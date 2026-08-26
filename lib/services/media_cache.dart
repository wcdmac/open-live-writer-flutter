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

  Directory? _base;
  final Set<String> _downloading = {};
  final Set<String> _failed = {};

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
  String _fileNameFor(String url) {
    final hash = (url.hashCode & 0x7fffffff).toRadixString(16);
    final tail = url.split('/').lastOrNull ?? '';
    final safe = tail.split('?').first.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    return '$hash-${safe.length > 48 ? safe.substring(safe.length - 48) : safe}';
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
  /// null on failure. Failures are remembered so a dead URL is not
  /// retried on every build.
  Future<File?> fetch(String url) async {
    if (!url.startsWith('http') ||
        _failed.contains(url) ||
        _downloading.contains(url)) {
      return existingFile(url);
    }
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
          _failed.add(url);
          return null;
        }
        await file.writeAsBytes(res.bodyBytes, flush: true);
      }
      return file;
    } catch (_) {
      _failed.add(url);
      return null;
    } finally {
      _downloading.remove(url);
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
