import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlparser;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/blog.dart';
import '../models/blog_post.dart';

/// Post export: single posts as a standalone HTML document or Markdown
/// file, the whole blog as a WordPress WXR (eXtended RSS) file that the
/// WP admin can re-import (Tools → Import → WordPress).
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

  /// File-system-safe name derived from the post title.
  static String safeName(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_')
        .replaceAll(RegExp(r'\s+'), '-');
    final name = cleaned.isEmpty ? 'untitled' : cleaned;
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
      if (post.authorName?.isNotEmpty == true) post.authorName!,
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
    fm.writeln('title: "${post.title.replaceAll('"', r'\"')}"');
    if (post.slug?.isNotEmpty == true) fm.writeln('slug: ${post.slug}');
    fm.writeln('status: ${post.status.wpValue}');
    if (post.datePublished != null) {
      fm.writeln('date: ${post.datePublished!.toIso8601String()}');
    }
    if (cats.isNotEmpty) {
      fm.writeln('categories: [${cats.map((c) => '"$c"').join(', ')}]');
    }
    if (post.tags.isNotEmpty) {
      fm.writeln('tags: [${post.tags.map((t) => '"$t"').join(', ')}]');
    }
    if (post.excerpt.trim().isNotEmpty) {
      fm.writeln('excerpt: "${post.excerpt.trim().replaceAll('"', r'\"')}"');
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

  // --- WXR -------------------------------------------------------------------

  /// Builds a WXR 1.2 document for [posts]. Taxonomies resolve names
  /// against the account's known [categories]/[tags].
  static String buildWxr(
    List<BlogPost> posts, {
    required BlogAccount account,
    List<PostCategory> categories = const [],
    List<PostTag> tags = const [],
  }) {
    final site = account.homepageUrl;
    final now = DateFormat('EEE, dd MMM yyyy HH:mm:ss +0000', 'en_US')
        .format(DateTime.now().toUtc());
    final out = StringBuffer();
    out.writeln('<?xml version="1.0" encoding="UTF-8" ?>');
    out.writeln('<rss version="2.0"');
    out.writeln('  xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/"');
    out.writeln('  xmlns:content="http://purl.org/rss/1.0/modules/content/"');
    out.writeln('  xmlns:wfw="http://wellformedweb.org/CommentAPI/"');
    out.writeln('  xmlns:dc="http://purl.org/dc/elements/1.1/"');
    out.writeln('  xmlns:wp="http://wordpress.org/export/1.2/">');
    out.writeln('<channel>');
    out.writeln('  <title>${_cdata(account.name)}</title>');
    out.writeln('  <link>$site</link>');
    out.writeln('  <description />');
    out.writeln('  <pubDate>$now</pubDate>');
    out.writeln('  <language>zh-CN</language>');
    out.writeln('  <wp:wxr_version>1.2</wp:wxr_version>');
    out.writeln('  <wp:base_site_url>$site</wp:base_site_url>');
    out.writeln('  <wp:base_blog_url>$site</wp:base_blog_url>');
    out.writeln('  <wp:author>');
    out.writeln('    <wp:author_id>1</wp:author_id>');
    out.writeln('    <wp:author_login>${_cdata(account.username)}</wp:author_login>');
    out.writeln('    <wp:author_email>${_cdata('')}</wp:author_email>');
    out.writeln(
        '    <wp:author_display_name>${_cdata(account.username)}</wp:author_display_name>');
    out.writeln('    <wp:author_first_name>${_cdata('')}</wp:author_first_name>');
    out.writeln('    <wp:author_last_name>${_cdata('')}</wp:author_last_name>');
    out.writeln('  </wp:author>');

    for (final category in categories) {
      out.writeln('  <wp:category>');
      out.writeln('    <wp:term_id>${category.id}</wp:term_id>');
      out.writeln(
          '    <wp:category_nicename>${category.slug ?? category.id}</wp:category_nicename>');
      out.writeln(
          '    <wp:category_parent>${_cdata(category.parentId ?? '')}</wp:category_parent>');
      out.writeln('    <wp:cat_name>${_cdata(category.name)}</wp:cat_name>');
      out.writeln('  </wp:category>');
    }
    for (final tag in tags) {
      out.writeln('  <wp:tag>');
      out.writeln('    <wp:term_id>${tag.id}</wp:term_id>');
      out.writeln('    <wp:tag_slug>${tag.slug ?? tag.id}</wp:tag_slug>');
      out.writeln('    <wp:tag_name>${_cdata(tag.name)}</wp:tag_name>');
      out.writeln('  </wp:tag>');
    }

    for (final post in posts) {
      final date = post.datePublished ?? post.dateCreated;
      final dateStr = date == null
          ? ''
          : DateFormat('yyyy-MM-dd HH:mm:ss').format(date.toLocal());
      final link = post.permalink ?? '$site/?p=${post.id}';
      out.writeln('  <item>');
      out.writeln('    <title>${_cdata(post.title)}</title>');
      out.writeln('    <link>$link</link>');
      out.writeln('    <pubDate>${date == null ? now : DateFormat('EEE, dd MMM yyyy HH:mm:ss +0000', 'en_US').format(date.toUtc())}</pubDate>');
      out.writeln('    <dc:creator>${_cdata(account.username)}</dc:creator>');
      out.writeln('    <guid isPermaLink="false">$link</guid>');
      out.writeln('    <description />');
      out.writeln(
          '    <content:encoded>${_cdata(post.content)}</content:encoded>');
      out.writeln(
          '    <excerpt:encoded>${_cdata(post.excerpt)}</excerpt:encoded>');
      out.writeln('    <wp:post_id>${post.id ?? 0}</wp:post_id>');
      out.writeln('    <wp:post_date>${_cdata(dateStr)}</wp:post_date>');
      out.writeln('    <wp:post_date_gmt>${_cdata(dateStr)}</wp:post_date_gmt>');
      out.writeln(
          '    <wp:comment_status>${_cdata(post.commentsEnabled ? 'open' : 'closed')}</wp:comment_status>');
      out.writeln(
          '    <wp:ping_status>${_cdata(post.pingsEnabled ? 'open' : 'closed')}</wp:ping_status>');
      out.writeln('    <wp:post_name>${_cdata(post.slug ?? '')}</wp:post_name>');
      out.writeln('    <wp:status>${_cdata(post.status.wpValue)}</wp:status>');
      out.writeln('    <wp:post_parent>0</wp:post_parent>');
      out.writeln('    <wp:menu_order>0</wp:menu_order>');
      out.writeln(
          '    <wp:post_type>${_cdata(post.isPage ? 'page' : 'post')}</wp:post_type>');
      out.writeln('    <wp:post_password>${_cdata('')}</wp:post_password>');
      out.writeln('    <wp:is_sticky>0</wp:is_sticky>');
      for (final catId in post.categories) {
        final cat = categories.where((c) => c.id == catId).firstOrNull;
        final name = cat?.name ?? catId;
        out.writeln(
            '    <category domain="category" nicename="${cat?.slug ?? catId}">${_cdata(name)}</category>');
      }
      for (final tagName in post.tags) {
        final tag = tags.where((t) => t.name == tagName).firstOrNull;
        out.writeln(
            '    <category domain="post_tag" nicename="${tag?.slug ?? tagName}">${_cdata(tagName)}</category>');
      }
      out.writeln('  </item>');
    }

    out.writeln('</channel>');
    out.writeln('</rss>');
    return out.toString();
  }

  // --- helpers -------------------------------------------------------------

  static String _esc(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// CDATA section; splits an embedded "]]>" so the document stays
  /// well-formed.
  static String _cdata(String raw) =>
      '<![CDATA[${raw.replaceAll(']]>', ']]]]><![CDATA[>')}]]>';
}
