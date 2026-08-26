import 'package:flutter_test/flutter_test.dart';
import 'package:open_live_writer/editor/block_document.dart';

void main() {
  test('round-trips a real WordPress hello-world post verbatim', () {
    const src = '<!-- wp:paragraph -->\n'
        '<p>欢迎使用 WordPress。这是您的第一篇文章。编辑或删除它，然后开始写作吧！</p>\n'
        '<!-- /wp:paragraph -->';
    final blocks = parseBlocks(src);
    expect(blocks.length, 1);
    expect(blocks.first.type, BlockType.paragraph);
    expect(blocks.first.wpOpen, '<!-- wp:paragraph -->');
    expect(blocks.first.wpClose, '<!-- /wp:paragraph -->');
    expect(serializeBlocks(blocks), src);
  });

  test('round-trips mixed content with attributes in block comments', () {
    const src = '<!-- wp:heading {"level":3} -->\n'
        '<h3>标题</h3>\n'
        '<!-- /wp:heading -->\n\n'
        '<!-- wp:image {"id":12} -->\n'
        '<figure><img src="https://x/a.jpg" alt="图" /></figure>\n'
        '<!-- /wp:image -->\n\n'
        '<p>普通<b>加粗</b>段落</p>\n\n'
        '<!-- wp:table -->\n'
        '<figure class="wp-block-table"><table><tbody><tr><th>A</th><th>B</th></tr>'
        '<tr><td>1</td><td>2</td></tr></tbody></table></figure>\n'
        '<!-- /wp:table -->\n\n'
        '<!-- wp:embed {"url":"https://www.youtube.com/watch?v=abc123"} -->\n'
        '<figure class="wp-block-embed is-provider-youtube wp-block-embed-youtube">'
        '<div class="wp-block-embed__wrapper">https://www.youtube.com/watch?v=abc123</div></figure>\n'
        '<!-- /wp:embed -->';
    final blocks = parseBlocks(src);
    expect(blocks.length, 5);
    expect(blocks[0].type, BlockType.heading);
    expect(blocks[1].type, BlockType.image);
    expect(blocks[2].type, BlockType.paragraph);
    expect(blocks[3].type, BlockType.table);
    expect(blocks[4].type, BlockType.video);
    expect(serializeBlocks(blocks), src);
  });

  test('unknown markup becomes a lossless html block', () {
    const src = '<div class="weird"><span>keep me</span></div>';
    final blocks = parseBlocks(src);
    expect(blocks.single.type, BlockType.html);
    expect(blocks.single.html, src);
    expect(serializeBlocks(blocks), src);
  });

  test('empty content produces no blocks', () {
    expect(parseBlocks(''), isEmpty);
    expect(parseBlocks('   \n\n  '), isEmpty);
  });

  test('plain text lines merge into a paragraph chunk until a blank line',
      () {
    final blocks = parseBlocks('第一行\n第二行\n\n<ol><li>item</li></ol>');
    expect(blocks.length, 2);
    expect(blocks[0].type, BlockType.paragraph);
    expect(blocks[0].html, '第一行\n第二行');
    expect(blocks[1].type, BlockType.list);
  });

  test('table helpers parse and serialize cells', () {
    const src =
        '<figure class="wp-block-table"><table class="has-fixed-layout"><thead><tr><th>Name</th><th>Qty</th></tr></thead>'
        '<tbody><tr><td>Apple &amp; Pear</td><td>2</td></tr></tbody></table></figure>';
    final table = parseTable(src);
    expect(table.rows.length, 2);
    expect(table.rows[1][0], 'Apple & Pear');
    expect(table.hasHeader, isTrue);
    final out = serializeTable(table);
    expect(out, src);
  });

  test('serializeTable emits Gutenberg-canonical markup without inline styles',
      () {
    // Inline border styles break Gutenberg block validation and stack
    // with theme CSS into uneven line widths — output must be bare.
    // The header row must live in <thead>; th inside <tbody> fails
    // Gutenberg's block validation.
    final out = serializeTable(TableData(rows: [
      ['A', 'B'],
      ['1', '2'],
    ], hasHeader: true));
    expect(out,
        '<figure class="wp-block-table"><table class="has-fixed-layout">'
        '<thead><tr><th>A</th><th>B</th></tr></thead>'
        '<tbody><tr><td>1</td><td>2</td></tr></tbody></table></figure>');
    expect(out, isNot(contains('style=')));
  });

  test('table alignment round-trips through has-text-align classes', () {
    // Gutenberg stores alignment on the figure wrapper, not the table.
    final out = serializeTable(TableData(rows: [
      ['A']
    ], align: TableCellAlign.center));
    expect(out, contains('<figure class="wp-block-table has-text-align-center">'));
    expect(out, contains('<table class="has-fixed-layout">'));
    // Left is the default and emits no class, matching Gutenberg.
    final left = serializeTable(TableData(rows: [
      ['A']
    ]));
    expect(left, contains('<figure class="wp-block-table">'));
    // Parsing picks the class back up.
    expect(parseTable(out).align, TableCellAlign.center);
  });

  test('code block helpers round-trip source with special characters', () {
    const src = 'int main() {\n  return x < y && y > z;\n}';
    final html = buildCodeHtml(src);
    expect(html,
        '<pre class="wp-block-code"><code>int main() {\n  return x &lt; y &amp;&amp; y &gt; z;\n}</code></pre>');
    expect(parseCodeBlock(html), src);
    // Bare <pre> without the code wrapper also parses.
    expect(parseCodeBlock('<pre>plain</pre>'), 'plain');
    // Non-code markup returns null (caller keeps the raw html).
    expect(parseCodeBlock('<p>not code</p>'), isNull);
  });

  test('buildVideoEmbed handles youtube links, media files and iframes', () {
    expect(
        buildVideoEmbed('https://www.youtube.com/watch?v=abc123XYZ'),
        contains('wp-block-embed-youtube'));
    expect(buildVideoEmbed('https://x/v.mp4'),
        '<video controls src="https://x/v.mp4"></video>');
    expect(buildVideoEmbed('https://example.com/live'),
        startsWith('<iframe src="https://example.com/live"'));
  });

  test('heading level helpers', () {
    expect(headingLevel('<h3>x</h3>'), 3);
    expect(setHeadingLevel('<h2>hello</h2>', 4), '<h4>hello</h4>');
  });

  test('image field helpers', () {
    const html = '<figure><img src="https://x/a.jpg" alt="描述" /></figure>';
    expect(firstImgSrc(html), 'https://x/a.jpg');
    expect(firstImgAlt(html), '描述');
  });

  test('generated media blocks match Gutenberg canonical markup', () {
    // Image: <img> inside wp-block-image figure (with/without caption).
    expect(buildImageHtml('https://x/a.jpg', '图'),
        '<figure class="wp-block-image"><img src="https://x/a.jpg" alt="图" /></figure>');
    expect(buildImageHtml('https://x/a.jpg', '', caption: '说明'),
        '<figure class="wp-block-image"><img src="https://x/a.jpg" alt="" />'
        '<figcaption>说明</figcaption></figure>');
    // Uploaded video: wp-block-video figure wrapper — a bare <video>
    // makes Gutenberg flag "invalid content" and themes left-align it.
    final v = buildVideoFileHtml('https://x/v.mp4');
    expect(v,
        '<figure class="wp-block-video"><video controls src="https://x/v.mp4"></video></figure>');
    // And both classify back into their block types.
    expect(parseBlocks(buildImageHtml('https://x/a.jpg', '')).single.type,
        BlockType.image);
    expect(parseBlocks(v).single.type, BlockType.video);
  });

  test('self-closing wp comment is preserved as html block', () {
    const src = '<!-- wp:latest-posts /-->';
    final blocks = parseBlocks(src);
    expect(blocks.single.type, BlockType.html);
    expect(serializeBlocks(blocks), src);
  });
}
