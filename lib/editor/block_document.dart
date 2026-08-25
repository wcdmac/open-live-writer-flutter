/// Block document model for the visual (WYSIWYG) editor.
///
/// A post's HTML is parsed into a flat list of [ContentBlock]s. WordPress
/// block comments (`<!-- wp:paragraph --> ... <!-- /wp:paragraph -->`) are
/// detected and preserved verbatim on round-trip, so editing a post in the
/// visual editor never strips Gutenberg markup. Unrecognized markup becomes
/// an [html] block that round-trips as raw source — nothing is ever lost.
library;

/// One editable block of the document.
class ContentBlock {
  ContentBlock({
    required this.type,
    required this.html,
    this.wpOpen,
    this.wpClose,
  });

  /// Block kind. Drives which editor widget renders it.
  final BlockType type;

  /// The block's inner HTML (WITHOUT the wp comments). This is the editable
  /// payload — e.g. `<p>hello <strong>world</strong></p>` for a paragraph.
  String html;

  /// Original `<!-- wp:xxx {"attrs":...} -->` opener, if the block had one.
  String? wpOpen;

  /// Original `<!-- /wp:xxx -->` closer, if the block had one.
  String? wpClose;

  /// Serialize back to post HTML, restoring the block comments.
  String serialize() {
    final open = wpOpen == null ? '' : '$wpOpen\n';
    final close = wpClose == null ? '' : '\n$wpClose';
    return '$open$html$close';
  }
}

/// Supported visual block kinds. Anything else falls back to [html].
enum BlockType {
  paragraph,
  heading,
  image,
  table,
  video,
  list,
  quote,
  code,
  html,
}

/// Matches a complete wp block with its paired closer. Block name in group 1
/// guarantees the closer belongs to the same opener.
final RegExp _wpBlockRe = RegExp(
    r'<!--\s*wp:([a-z0-9/-]+)([^>]*)-->([\s\S]*?)<!--\s*/wp:\1\s*-->',
    caseSensitive: false);

/// Self-closing wp comment, e.g. `<!-- wp:latest-posts /-->`.
final RegExp _wpSelfClosingRe =
    RegExp(r'<!--\s*wp:[a-z0-9/-]+[^>]*/\s*-->', caseSensitive: false);

/// Parses post HTML into blocks. Splitting strategy:
/// 1. Scan for paired wp block comments — each pair is one block, verbatim.
/// 2. Remaining text splits on blank lines (`\n\s*\n`) into chunks.
/// 3. Classify each chunk; unknown shapes become [BlockType.html].
List<ContentBlock> parseBlocks(String content) {
  final text = content.trim();
  if (text.isEmpty) return [];

  final blocks = <ContentBlock>[];
  var pos = 0;

  void addChunk(String chunk) {
    final trimmed = chunk.trim();
    if (trimmed.isNotEmpty) blocks.add(_classify(trimmed));
  }

  while (pos < text.length) {
    // Skip inter-block whitespace.
    final ws = RegExp(r'\s+').matchAsPrefix(text, pos);
    if (ws != null) {
      pos += ws.end - ws.start;
      if (pos >= text.length) break;
    }

    // A wp block pair starting exactly here?
    final pair = _wpBlockRe.matchAsPrefix(text, pos);
    if (pair != null) {
      final whole = pair.group(0)!;
      final inner = pair.group(3)!;
      final opener = RegExp(r'<!--[^>]*-->').firstMatch(whole)!;
      blocks.add(_classify(
        inner.trim(),
        wpOpen: whole.substring(0, opener.end),
        wpClose: whole.substring(opener.end + inner.length),
      ));
      pos = pair.end;
      continue;
    }

    // A self-closing wp comment here?
    final selfClosing = _wpSelfClosingRe.matchAsPrefix(text, pos);
    if (selfClosing != null) {
      blocks.add(ContentBlock(
          type: BlockType.html, html: text.substring(pos, selfClosing.end)));
      pos = selfClosing.end;
      continue;
    }

    // Plain chunk: up to the next blank line, next wp comment or EOF.
    final nextBlank = RegExp(r'\n\s*\n').firstMatch(text.substring(pos + 1));
    final nextWp = _wpBlockRe
        .allMatches(text, pos + 1)
        .map((m) => m.start)
        .firstOrNull;
    final nextSelf = _wpSelfClosingRe
        .allMatches(text, pos + 1)
        .map((m) => m.start)
        .firstOrNull;
    var end = text.length;
    if (nextBlank != null) end = pos + 1 + nextBlank.start;
    if (nextWp != null && nextWp < end) end = nextWp;
    if (nextSelf != null && nextSelf < end) end = nextSelf;

    addChunk(text.substring(pos, end));
    pos = end;
  }
  return blocks;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Serializes blocks back into post HTML.
String serializeBlocks(List<ContentBlock> blocks) =>
    blocks.map((b) => b.serialize()).join('\n\n');

/// Classifies a chunk of HTML into a [ContentBlock].
ContentBlock _classify(String html, {String? wpOpen, String? wpClose}) {
  final type = _classifyType(html);
  return ContentBlock(type: type, html: html, wpOpen: wpOpen, wpClose: wpClose);
}

BlockType _classifyType(String html) {
  final h = html.trim();
  if (h.isEmpty) return BlockType.html;

  // Images: bare <img>, <figure> wrapping an img, or wp image blocks.
  if (RegExp(r'^<img\b', caseSensitive: false).hasMatch(h) ||
      (RegExp(r'^<figure\b', caseSensitive: false).hasMatch(h) &&
          RegExp(r'<img\b', caseSensitive: false).hasMatch(h) &&
          !RegExp(r'<table\b', caseSensitive: false).hasMatch(h))) {
    return BlockType.image;
  }

  // Video / embeds: <video>, <iframe>, wp embed/figure-with-iframe.
  if (RegExp(r'^(<video|<iframe|<figure[^>]*wp-block-embed)\b',
          caseSensitive: false)
      .hasMatch(h)) {
    return BlockType.video;
  }

  // Tables (bare or wrapped in a wp-block-table figure).
  if (RegExp(r'^<table\b', caseSensitive: false).hasMatch(h) ||
      (RegExp(r'^<figure[^>]*wp-block-table', caseSensitive: false)
              .hasMatch(h) &&
          RegExp(r'<table\b', caseSensitive: false).hasMatch(h))) {
    return BlockType.table;
  }

  // Headings.
  if (RegExp(r'^<h[1-6]\b', caseSensitive: false).hasMatch(h)) {
    return BlockType.heading;
  }

  // Lists.
  if (RegExp(r'^<[uo]l\b', caseSensitive: false).hasMatch(h)) {
    return BlockType.list;
  }

  // Blockquotes.
  if (RegExp(r'^<blockquote\b', caseSensitive: false).hasMatch(h)) {
    return BlockType.quote;
  }

  // Code blocks.
  if (RegExp(r'^<pre\b', caseSensitive: false).hasMatch(h)) {
    return BlockType.code;
  }

  // Everything else with a single <p> wrapper (or plain text) is a paragraph.
  if (RegExp(r'^<p\b', caseSensitive: false).hasMatch(h) ||
      !h.startsWith('<')) {
    return BlockType.paragraph;
  }

  return BlockType.html;
}

// ---------------------------------------------------------------------------
// Field-level helpers used by the visual editor widgets.
// ---------------------------------------------------------------------------

/// Extracts the src attribute of the first <img> in [html].
String? firstImgSrc(String html) {
  final m = RegExp(r'<img[^>]*\bsrc="([^"]+)"', caseSensitive: false)
      .firstMatch(html);
  return m?.group(1);
}

/// Extracts the alt attribute of the first <img> in [html].
String? firstImgAlt(String html) {
  final m = RegExp(r'<img[^>]*\balt="([^"]*)"', caseSensitive: false)
      .firstMatch(html);
  return m?.group(1);
}

/// Heading level (1-6) from `<hN>` markup, defaulting to 2.
int headingLevel(String html) {
  final m = RegExp(r'^<h([1-6])\b', caseSensitive: false).firstMatch(html);
  return m == null ? 2 : int.parse(m.group(1)!);
}

/// Rewrites the heading level, keeping inner content.
String setHeadingLevel(String html, int level) {
  final inner = RegExp(r'^<h[1-6][^>]*>([\s\S]*)</h[1-6]>\s*$',
          caseSensitive: false)
      .firstMatch(html
          .trim());
  final content = inner?.group(1) ?? html;
  return '<h$level>$content</h$level>';
}

/// The first URL inside an embed/video block (iframe src, video src or the
/// bare link text) — used to prefill the video URL field.
String? firstEmbedUrl(String html) {
  for (final attr in const ['src', 'data-src']) {
    final m = RegExp('<[a-z]+[^>]*\\b$attr="([^"]+)"', caseSensitive: false)
        .firstMatch(html);
    if (m != null) return m.group(1);
  }
  final link = RegExp(r'https?://[^\s"<]+').firstMatch(html);
  return link?.group(0);
}

/// Builds a WordPress video embed for [url].
///
/// Plain YouTube/Vimeo links become the wp:embed form (WordPress core
/// converts these to embeds automatically); other URLs become a <video> tag
/// when they look like a media file, else an iframe.
String buildVideoEmbed(String url) {
  final u = url.trim();
  final yt = RegExp(
          r'^(?:https?://)?(?:www\.|m\.)?youtube\.com/watch\?v=([\w-]{6,})')
      .firstMatch(u);
  if (yt != null) {
    return '<figure class="wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube wp-embed-aspect-16-9 wp-has-aspect-ratio">'
        '<div class="wp-block-embed__wrapper">\n'
        'https://www.youtube.com/watch?v=${yt.group(1)}\n'
        '</div></figure>';
  }
  if (RegExp(r'\.(mp4|webm|ogg|m4v)(\?|$)', caseSensitive: false)
      .hasMatch(u)) {
    return '<video controls src="$u"></video>';
  }
  return '<iframe src="$u" width="640" height="360" frameborder="0" '
      'allowfullscreen></iframe>';
}

/// Builds a simple 2x2 starter table (1 header row + 1 body row).
String buildTable({int rows = 2, int cols = 2}) {
  final buf = StringBuffer('<figure class="wp-block-table"><table><tbody>');
  for (var r = 0; r < rows; r++) {
    buf.write('<tr>');
    for (var c = 0; c < cols; c++) {
      buf.write(r == 0 ? '<th></th>' : '<td></td>');
    }
    buf.write('</tr>');
  }
  buf.write('</tbody></table></figure>');
  return buf.toString();
}

/// Parses `<figure class="wp-block-table"><table>...` (or a bare table)
/// into a cell matrix. The first row is the header (th).
TableData parseTable(String html) {
  final rowRe = RegExp(r'<tr[^>]*>([\s\S]*?)</tr>', caseSensitive: false);
  final cellRe = RegExp(r'<t[hd][^>]*>([\s\S]*?)</t[hd]>', caseSensitive: false);
  final rows = <List<String>>[];
  var hasHeader = false;
  for (final rowMatch in rowRe.allMatches(html)) {
    final cells = <String>[];
    for (final cell in cellRe.allMatches(rowMatch.group(1)!)) {
      cells.add(_decodeEntities(cell.group(1)!.trim()));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isNotEmpty && RegExp(r'<th\b', caseSensitive: false).hasMatch(html)) {
    hasHeader = true;
  }
  return TableData(rows: rows, hasHeader: hasHeader);
}

/// Encodes a cell matrix back into table HTML inside a wp-block-table
/// figure (when the source had one).
String serializeTable(TableData table, {bool wrapFigure = true}) {
  final buf = StringBuffer('<table><tbody>');
  for (var r = 0; r < table.rows.length; r++) {
    buf.write('<tr>');
    final isHeader = table.hasHeader && r == 0;
    for (final cell in table.rows[r]) {
      final tag = isHeader ? 'th' : 'td';
      buf.write('<$tag>${_encodeEntities(cell)}</$tag>');
    }
    buf.write('</tr>');
  }
  buf.write('</tbody></table>');
  if (!wrapFigure) return buf.toString();
  return '<figure class="wp-block-table">${buf.toString()}</figure>';
}

/// Editable table payload.
class TableData {
  TableData({required this.rows, this.hasHeader = false});

  List<List<String>> rows;
  bool hasHeader;

  int get columnCount => rows.isEmpty ? 0 : rows.reduce((a, b) => a.length >= b.length ? a : b).length;
}

String _decodeEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"');

String _encodeEntities(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
