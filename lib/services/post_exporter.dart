import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlparser;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/blog_post.dart';

/// Post export: single posts as a standalone HTML document or Markdown
/// file. Whole-blog export is intentionally NOT offered here — the
/// WordPress admin's own export (Tools → Export) is strictly more
/// complete (media files, comments, postmeta, all authors).
class PostExporter {
  /// Where exported files land.
  ///
  /// iOS: the app's Documents folder. With UIFileSharingEnabled in
  /// Info.plist it appears in the Files app under "On My iPhone" →
  /// Open Live Writer, is reachable from the share sheet, and is
  /// deleted together with the app on uninstall (no orphaned files).
  /// The container's Downloads folder is NOT visible in the Files app,
  /// so it must not be used there.
  ///
  /// Other platforms: the user's Downloads folder, created on demand.
  static Future<String> exportDir() async {
    if (Platform.isIOS) {
      return (await getApplicationDocumentsDirectory()).path;
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads.path;
      }
    } catch (_) {
      // Fall through to the documents folder.
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  static Future<File> write(String fileName, String contents) async {
    final dir = await exportDir();
    final file = File('$dir${Platform.pathSeparator}$fileName');
    await file.writeAsString(contents, flush: true);
    return file;
  }

  /// DOS device names: still unwritable on Windows even with an extension.
  static const _reservedNames = {
    'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// File-system-safe name derived from the post title.
  static String safeName(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_')
        .replaceAll(RegExp(r'\s+'), '-');
    // Separators are already stripped above, but a bare "." or ".." is still
    // a path-navigation hazard, and the reserved names cannot be written.
    var name = cleaned.replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (name.isEmpty) name = 'untitled';
    if (_reservedNames.contains(name.toLowerCase())) name = '${name}_';
    return name.length > 60 ? name.substring(0, 60) : name;
  }

  static String postFileName(BlogPost post, String ext) =>
      '${safeName(post.title)}${post.id == null ? '' : '-${post.id}'}.$ext';

  // --- HTML -----------------------------------------------------------------

  /// Standalone HTML document wrapping the ORIGINAL block markup. The
  /// inner markup (WP block comments included) can be pasted straight
  /// into a post's code editor to re-import with blocks intact.
  static String buildHtmlDocument(BlogPost post) {
    final meta = [
      if (post.datePublished != null)
        DateFormat('yyyy-MM-dd').format(post.datePublished!.toLocal()),
      post.status.label,
      // Escape: author names are server data and this is raw HTML output.
      if (post.authorName?.isNotEmpty == true) _esc(post.authorName!),
    ].join(' · ');
    return '<!DOCTYPE html>\n'
        '<html>\n'
        '<head>\n'
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1">\n'
        '<title>${_esc(post.title)}</title>\n'
        '<style>body{max-width:720px;margin:2rem auto;padding:0 1rem;'
        'font-family:system-ui,sans-serif;line-height:1.7}'
        '.meta{color:#666;font-size:0.9em}img{max-width:100%}</style>\n'
        '</head>\n'
        '<body>\n'
        '<article>\n'
        '<h1>${_esc(post.title)}</h1>\n'
        '<p class="meta">$meta</p>\n'
        '${post.content}\n'
        '</article>\n'
        '</body>\n'
        '</html>\n';
  }

  // --- Markdown ---------------------------------------------------------------

  /// Converts the post to Markdown with a YAML front-matter header.
  /// [categoryName] resolves category ids to display names.
  static String toMarkdown(
    BlogPost post, {
    String Function(String categoryId)? categoryName,
  }) {
    final cats = post.categories
        .map((c) => categoryName != null ? categoryName(c) : c)
        .where((c) => c.trim().isNotEmpty)
        .toList();
    final fm = StringBuffer('---\n');
    fm.writeln('title: "${_yamlQuote(post.title)}"');
    if (post.slug?.isNotEmpty == true) fm.writeln('slug: ${post.slug}');
    fm.writeln('status: ${post.status.wpValue}');
    if (post.datePublished != null) {
      fm.writeln('date: ${post.datePublished!.toIso8601String()}');
    }
    if (cats.isNotEmpty) {
      fm.writeln('categories: [${cats.map((c) => '"${_yamlQuote(c)}"').join(', ')}]');
    }
    if (post.tags.isNotEmpty) {
      fm.writeln('tags: [${post.tags.map((t) => '"${_yamlQuote(t)}"').join(', ')}]');
    }
    if (post.excerpt.trim().isNotEmpty) {
      fm.writeln('excerpt: "${_yamlQuote(post.excerpt.trim())}"');
    }
    fm.writeln('---\n');

    final body =
        _nodesToMarkdown(htmlparser.parseFragment(post.content).nodes)
            .trim();
    return '${fm.toString()}\n$body\n';
  }

  static String _nodesToMarkdown(Iterable<dom.Node> nodes) {
    final out = StringBuffer();
    for (final node in nodes) {
      if (node is dom.Element) {
        out.write(_elementToMarkdown(node));
      } else if (node is dom.Text) {
        out.write(node.text.replaceAll(RegExp(r'\s+'), ' '));
      }
      // Comments (WP block markup) are intentionally dropped.
    }
    return out.toString();
  }

  static String _inline(dom.Element element) =>
      _nodesToMarkdown(element.nodes);

  static String _elementToMarkdown(dom.Element element) {
    switch (element.localName) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(element.localName![1]);
        return '\n\n${'#' * level} ${_inline(element).trim()}\n\n';
      case 'p':
        return '\n\n${_inline(element).trim()}\n\n';
      case 'br':
        return '\n';
      case 'strong':
      case 'b':
        return '**${_inline(element).trim()}**';
      case 'em':
      case 'i':
        return '*${_inline(element).trim()}*';
      case 'del':
      case 's':
        return '~~${_inline(element).trim()}~~';
      case 'code':
        return '`${element.text}`';
      case 'a':
        final href = element.attributes['href'] ?? '';
        return '[${_inline(element).trim()}]($href)';
      case 'img':
        final src = element.attributes['src'] ?? '';
        final alt = element.attributes['alt'] ?? '';
        return '![${alt.replaceAll('[', '(').replaceAll(']', ')')}]($src)';
      case 'figure':
        return '\n\n${_inline(element).trim()}\n\n';
      case 'figcaption':
        return '\n*${_inline(element).trim()}*\n';
      case 'ul':
      case 'ol':
        final ordered = element.localName == 'ol';
        final out = StringBuffer('\n');
        var i = 1;
        for (final child in element.children) {
          if (child.localName != 'li') continue;
          final marker = ordered ? '$i.' : '-';
          out.writeln('$marker ${_inline(child).trim()}');
          i++;
        }
        return '$out\n';
      case 'blockquote':
        final inner = _nodesToMarkdown(element.nodes).trim();
        final quoted = inner
            .split('\n')
            .map((line) => line.isEmpty ? '>' : '> $line')
            .join('\n');
        return '\n\n$quoted\n\n';
      case 'pre':
        return '\n\n```\n${element.text}\n```\n\n';
      case 'hr':
        return '\n\n---\n\n';
      case 'table':
        // Tables pass through as HTML: GFM pipe tables cannot express
        // merged cells / alignment attributes losslessly.
        return '\n\n${element.outerHtml}\n\n';
      default:
        // div/section/article/span/figure wrappers and unknown blocks:
        // recurse into children, keep the text flow.
        return _nodesToMarkdown(element.nodes);
    }
  }

  // --- helpers -------------------------------------------------------------

  /// Escapes a value for a YAML double-quoted scalar.
  ///
  /// Only quotes were escaped before, so a title or excerpt containing a
  /// newline broke the front matter into invalid YAML.
  static String _yamlQuote(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', r'\"')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');

  static String _esc(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
