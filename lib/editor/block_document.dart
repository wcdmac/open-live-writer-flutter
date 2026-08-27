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

  // Video / embeds: <video>, <iframe>, wp embed/figure-with-iframe or
  // the Gutenberg wp-block-video figure.
  if (RegExp(
          r'^(<video|<iframe|<figure[^>]*(wp-block-embed|wp-block-video))\b',
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

/// Extracts the plain-text payload of a code block (`wp:code` saves as
/// `<pre class="wp-block-code"><code>escaped</code></pre>`; bare `<pre>`
/// content is accepted too). Returns null when [html] is not a code block.
String? parseCodeBlock(String html) {
  final m = RegExp(
          r'^\s*<pre[^>]*>\s*(?:<code[^>]*>)?([\s\S]*?)(?:</code>)?\s*</pre>\s*$',
          caseSensitive: false)
      .firstMatch(html);
  return m == null ? null : _decodeEntities(m.group(1)!);
}

/// Wraps code text into Gutenberg core/code markup. Entities are escaped
/// so angle brackets and ampersands in source code survive the round trip.
String buildCodeHtml(String code) =>
    '<pre class="wp-block-code"><code>${_encodeEntities(code)}</code></pre>';

/// Normalizes a picked image for upload.
///
/// WordPress rejects formats that are not in the site's allowed MIME list
/// (HEIC from iOS cameras is the common offender). Since the image picker
/// re-encodes to JPEG whenever imageQuality/maxWidth are set, files whose
/// reported MIME is not whitelisted are renamed to `.jpg` and typed as
/// `image/jpeg` before hitting `wp.uploadFile`.
(String, String) normalizeImageUpload(String name, String mime) {
  const allowed = {'image/jpeg', 'image/png', 'image/gif', 'image/webp'};
  final m = mime.toLowerCase().split(';').first.trim();
  if (allowed.contains(m)) return (name, m);
  final base = name.contains('.')
      ? name.substring(0, name.lastIndexOf('.'))
      : name;
  return ('$base.jpg', 'image/jpeg');
}

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

/// Canonical Gutenberg image-block inner HTML: the <img> must sit inside
/// a `wp-block-image` figure or the block editor reports "invalid content"
/// and frontend themes have no centering styles.
String buildImageHtml(String src, String alt,
    {String? caption, String? figureClass, String? imgAttrs}) {
  final img = '<img src="$src" alt="$alt"${imgAttrs == null ? '' : ' $imgAttrs'} />';
  final cap = (caption == null || caption.trim().isEmpty)
      ? ''
      : '<figcaption>${caption.trim()}</figcaption>';
  return '<figure class="${figureClass ?? 'wp-block-image'}">$img$cap</figure>';
}

/// Canonical Gutenberg video-block inner HTML (uploaded media file):
/// `wp-block-video` figure wrapper, matching the block editor's own
/// output so frontend alignment styles apply.
String buildVideoFileHtml(String url) =>
    '<figure class="wp-block-video"><video controls src="$url">'
    '</video></figure>';

/// Heading level (1-6) from `<hN>` markup, defaulting to 2.
int headingLevel(String html) {
  final m = RegExp(r'^<h([1-6])\b', caseSensitive: false).firstMatch(html);
  return m == null ? 2 : int.parse(m.group(1)!);
}

/// Rewrites the heading level, keeping inner content AND the original
/// attributes (custom classes, ids) — a bare `<hN>` round-trip used to
/// strip them on every edit.
String setHeadingLevel(String html, int level) {
  final trimmed = html.trim();
  final m = RegExp(r'^<h[1-6]([^>]*)>([\s\S]*)</h[1-6]>\s*$',
          caseSensitive: false)
      .firstMatch(trimmed);
  if (m == null) return trimmed;
  return '<h$level${m.group(1)}>${m.group(2)}</h$level>';
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
  // Canonicalize youtu.be short links to the watch form so they take the
  // wp:embed path instead of degrading to a bare iframe.
  final short = RegExp(r'^(?:https?://)?youtu\.be/([\w-]{6,})').firstMatch(u);
  if (short != null) {
    return buildVideoEmbed(
        'https://www.youtube.com/watch?v=${short.group(1)}');
  }
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

/// Builds a simple 2x2 starter table (1 header row + 1 body row), bordered
/// by default so the lines are visible on any theme.
String buildTable({int rows = 2, int cols = 2}) {
  final table = TableData(rows: [
    for (var r = 0; r < rows; r++) List.filled(cols, '', growable: true),
  ], hasHeader: true, hasBorder: true);
  return serializeTable(table);
}

/// Parses `<figure class="wp-block-table"><table>...` (or a bare table)
/// into a cell matrix. The first row is the header only when IT uses <th>
/// cells — a th anywhere else (mid-table) must not flip the whole table
/// into thead/tbody mode, which would restructure the markup on save.
TableData parseTable(String html) {
  final rowRe = RegExp(r'<tr[^>]*>([\s\S]*?)</tr>', caseSensitive: false);
  final cellRe = RegExp(r'<t[hd][^>]*>([\s\S]*?)</t[hd]>', caseSensitive: false);
  final rows = <List<String>>[];
  var hasHeader = false;
  String? caption;
  final capMatch = RegExp(r'<figcaption[^>]*>([\s\S]*?)</figcaption>',
          caseSensitive: false)
      .firstMatch(html);
  if (capMatch != null) {
    caption = _decodeEntities(capMatch.group(1)!.trim());
    if (caption.isEmpty) caption = null;
  }
  for (final rowMatch in rowRe.allMatches(html)) {
    final cells = <String>[];
    for (final cell in cellRe.allMatches(rowMatch.group(1)!)) {
      cells.add(_decodeEntities(cell.group(1)!.trim()));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  // Header = <th> cells in the FIRST row only.
  if (rows.isNotEmpty) {
    final firstRow = rowRe.firstMatch(html);
    hasHeader = firstRow != null &&
        RegExp(r'<th\b', caseSensitive: false).hasMatch(firstRow.group(0)!);
  }
  final hasBorder = RegExp(
          r'style\s*=\s*"[^"]*border|<table[^>]*\bborder\b',
          caseSensitive: false)
      .hasMatch(html);
  // Gutenberg stores alignment as has-text-align-* classes on the figure
  // or the table; legacy content may use style="text-align:*". The figure
  // class comes first in the markup, so scan every class/style attribute.
  TableCellAlign? align;
  for (final m in RegExp(r'(?:class|style)\s*=\s*"([^"]*)"',
          caseSensitive: false)
      .allMatches(html)) {
    align = TableCellAlign.fromStyle(m.group(1)!);
    if (align != null) break;
  }
  return TableData(
    rows: rows,
    hasHeader: hasHeader,
    hasBorder: hasBorder,
    align: align ?? TableCellAlign.left,
    caption: caption,
  );
}

/// Serializes back to Gutenberg-canonical table markup:
/// `figure.wp-block-table [has-text-align-*] > table.has-fixed-layout >
/// thead(th) + tbody(td)`. Gutenberg puts the header row in `<thead>` —
/// `th` cells inside `<tbody>` fail its block validation ("unexpected or
/// invalid content") — and stores text alignment as a class on the
/// figure, not the table.
/// No inline border styles — they break validation and stack with theme
/// CSS into uneven line widths. Frontend borders come from WordPress core
/// block styles (`.wp-block-table td/th { border: 1px solid }`).
String serializeTable(TableData table, {bool wrapFigure = true}) {
  final buf = StringBuffer('<table class="has-fixed-layout">');
  if (table.hasHeader && table.rows.isNotEmpty) {
    buf.write('<thead><tr>');
    for (final cell in table.rows[0]) {
      buf.write('<th>${_encodeEntities(cell)}</th>');
    }
    buf.write('</tr></thead>');
  }
  buf.write('<tbody>');
  for (var r = table.hasHeader ? 1 : 0; r < table.rows.length; r++) {
    buf.write('<tr>');
    for (final cell in table.rows[r]) {
      buf.write('<td>${_encodeEntities(cell)}</td>');
    }
    buf.write('</tr>');
  }
  buf.write('</tbody></table>');
  if (!wrapFigure) return buf.toString();
  final align =
      table.align == TableCellAlign.left ? '' : ' ${table.align.cssClass}';
  final cap = (table.caption == null || table.caption!.trim().isEmpty)
      ? ''
      : '<figcaption>${_encodeEntities(table.caption!)}</figcaption>';
  return '<figure class="wp-block-table$align">${buf.toString()}$cap</figure>';
}

/// Horizontal text alignment inside table cells. The string values are the
/// CSS/Gutenberg classes written into the table markup.
enum TableCellAlign { left('has-text-align-left'), center('has-text-align-center'), right('has-text-align-right');

  const TableCellAlign(this.cssClass);
  final String cssClass;

  /// Parses Gutenberg `has-text-align-*` classes (or a legacy
  /// `text-align:*` style) from a class/style attribute value.
  static TableCellAlign? fromStyle(String styleOrClass) {
    if (RegExp(r'has-text-align-center|text-align:\s*center', caseSensitive: false)
        .hasMatch(styleOrClass)) {
      return TableCellAlign.center;
    }
    if (RegExp(r'has-text-align-right|text-align:\s*right', caseSensitive: false)
        .hasMatch(styleOrClass)) {
      return TableCellAlign.right;
    }
    if (RegExp(r'has-text-align-left|text-align:\s*left', caseSensitive: false)
        .hasMatch(styleOrClass)) {
      return TableCellAlign.left;
    }
    return null;
  }
}

/// Editable table payload.
class TableData {
  TableData({
    required this.rows,
    this.hasHeader = false,
    this.hasBorder = false,
    this.align = TableCellAlign.left,
    this.caption,
  });

  List<List<String>> rows;
  bool hasHeader;
  bool hasBorder;

  /// Optional <figcaption> text; preserved across edits (it used to be
  /// dropped, silently deleting the user's caption).
  String? caption;

  /// Table-wide horizontal alignment (Gutenberg's alignment applies to the
  /// whole block; per-cell alignment is not part of the core table block).
  TableCellAlign align;

  int get columnCount => rows.isEmpty ? 0 : rows.reduce((a, b) => a.length >= b.length ? a : b).length;
}

// ---------------------------------------------------------------------------
// List block (core/list): items are the inner HTML of each <li> so inline
// formatting (links, bold) survives editing verbatim.
// ---------------------------------------------------------------------------

/// Editable list payload.
class ListData {
  ListData({required this.items, this.ordered = false, this.openTag});

  /// Inner HTML of each `<li>` — raw markup, edited as-is.
  List<String> items;
  bool ordered;

  /// Original `<ul>/<ol ...>` opening tag (classes like wp-block-list with
  /// extra styles); null uses the canonical default.
  String? openTag;
}

/// Top-level `<li>` items of a list, skipping items of NESTED lists: the
/// naive `<li>(.*?)</li>` regex closes the outer item at the first inner
/// `</li>`, corrupting nested-list markup on round-trip.
List<String> _topLevelListItems(String html) {
  final items = <String>[];
  final tagRe = RegExp(r'<(/?)(ul|ol|li)\b[^>]*>', caseSensitive: false);
  var listDepth = 0; // open <ul>/<ol> not yet closed
  var liStart = -1;
  var liDepth = 0;
  for (final m in tagRe.allMatches(html)) {
    final closing = m.group(1) == '/';
    final tag = m.group(2)!.toLowerCase();
    if (tag == 'li') {
      if (!closing && liStart == -1) {
        liStart = m.end;
        liDepth = listDepth;
      } else if (closing && liStart != -1 && listDepth == liDepth) {
        final inner = html.substring(liStart, m.start).trim();
        if (inner.isNotEmpty) items.add(inner);
        liStart = -1;
      }
    } else {
      listDepth += closing ? -1 : 1;
    }
  }
  return items;
}

/// Parses `<ul>/<ol>` markup (with or without wp:list-item comments).
ListData parseList(String html) {
  final ordered =
      RegExp(r'<ol\b', caseSensitive: false).hasMatch(html);
  // Strip optional wp:list-item wrappers; both legacy (bare <li>) and
  // modern (WP 6.7+) markup parse into the same shape.
  final cleaned = html
      .replaceAll(RegExp(r'<!--\s*wp:list-item\s*-->', caseSensitive: false), '')
      .replaceAll(RegExp(r'<!--\s*/wp:list-item\s*-->', caseSensitive: false), '');
  // Preserve the original opening tag (extra classes/attrs) on round-trip.
  final openMatch = RegExp(r'<(ul|ol)\b[^>]*>', caseSensitive: false)
      .firstMatch(cleaned);
  final items = _topLevelListItems(cleaned);
  return ListData(
      items: items,
      ordered: ordered,
      openTag: openMatch?.group(0));
}

/// Serializes to Gutenberg core/list markup with wp:list-item inner block
/// comments (WP 6.7+ canonical; older WP versions migrate it transparently).
String buildListHtml(ListData list) {
  final tag = list.ordered ? 'ol' : 'ul';
  final open = list.openTag ?? '<$tag class="wp-block-list">';
  final items = list.items
      .map((i) => '<!-- wp:list-item -->\n<li>$i</li>\n<!-- /wp:list-item -->')
      .join();
  return '$open$items</$tag>';
}

// ---------------------------------------------------------------------------
// Quote block (core/quote): paragraphs are the inner HTML of each <p>.
// ---------------------------------------------------------------------------

/// Editable quote payload.
class QuoteData {
  QuoteData({required this.paragraphs, this.openTag});

  /// Inner HTML of each `<p>` inside the blockquote.
  List<String> paragraphs;

  /// Original `<blockquote ...>` opening tag (preserves classes like
  /// is-style-plain / has-text-align-*); null uses the default.
  String? openTag;
}

/// Parses blockquote markup. Returns null for non-quote html.
QuoteData? parseQuote(String html) {
  final open =
      RegExp(r'<blockquote[^>]*>', caseSensitive: false).firstMatch(html);
  if (open == null) return null;
  final openTag = open.group(0)!;
  final paragraphs =
      RegExp(r'<p[^>]*>([\s\S]*?)</p>', caseSensitive: false)
          .allMatches(html)
          .map((m) => m.group(1)!.trim())
          .where((s) => s.isNotEmpty)
          .toList();
  if (paragraphs.isEmpty) {
    // Quote without <p> wrappers: treat the raw inner text as one paragraph.
    final inner = html
        .replaceAll(RegExp(r'</?blockquote[^>]*>', caseSensitive: false), '')
        .trim();
    if (inner.isEmpty) return QuoteData(paragraphs: [], openTag: openTag);
    return QuoteData(paragraphs: [inner], openTag: openTag);
  }
  return QuoteData(paragraphs: paragraphs, openTag: openTag);
}

/// Serializes to Gutenberg core/quote markup: each paragraph is an inner
/// wp:paragraph block, matching how the block editor saves quotes.
String buildQuoteHtml(QuoteData quote) {
  final open = quote.openTag ?? '<blockquote class="wp-block-quote">';
  final inner = quote.paragraphs
      .map((p) => '<!-- wp:paragraph -->\n<p>$p</p>\n<!-- /wp:paragraph -->')
      .join();
  return '$open$inner</blockquote>';
}

String _decodeEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'&#0?39;|&apos;'), "'")
    .replaceAll('&nbsp;', '\u00A0')
    // Numeric entities (decimal and hex).
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    })
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });

String _encodeEntities(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
