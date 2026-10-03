import 'package:flutter_test/flutter_test.dart';
import 'package:open_live_writer/editor/block_document.dart';
import 'package:open_live_writer/editor/editor_controller.dart';

/// Blocks are split on blank lines (`\n\n`); adjacent `<p>` on one line parse
/// as a single block. Keep sample content separated accordingly.
const String _three =
    '<p>A</p>\n\n<p>B</p>\n\n<p>C</p>';

ContentBlock _para(String html) => ContentBlock(
      type: BlockType.paragraph,
      html: html,
      wpOpen: '<!-- wp:paragraph -->',
      wpClose: '<!-- /wp:paragraph -->',
    );

void main() {
  test('parses initial content into blocks and does not re-emit', () {
    String? emitted;
    final c = EditorController(
      initialContent: _three,
      onChanged: (s) => emitted = s,
    );
    expect(c.blocks.length, 3);
    expect(c.content, contains('<p>A</p>'));
    expect(emitted, isNull); // initial content is not re-emitted
  });

  test('updateHtml rewrites the block and emits', () async {
    String? emitted;
    final c = EditorController(
      initialContent: _three,
      onChanged: (s) => emitted = s,
    );
    c.updateHtml(0, '<p>Changed</p>');
    expect(c.blocks[0].html, '<p>Changed</p>');
    // onChanged is debounced (P3-10); wait out the coalescing window before
    // asserting the propagated value.
    await Future.delayed(const Duration(milliseconds: 150));
    expect(emitted, contains('<p>Changed</p>'));
  });

  test('insert appends when nothing focused and focuses the new block', () {
    final c = EditorController(initialContent: '<p>One</p>');
    c.insert(_para('<p>Two</p>'));
    expect(c.blocks.length, 2);
    expect(c.focusedIndex, 1);
    expect(c.content, contains('<p>Two</p>'));
  });

  test('insert places after the focused block', () {
    final c = EditorController(initialContent: _three);
    c.focus(0);
    c.insert(_para('<p>X</p>'));
    expect(c.blocks.length, 4);
    expect(c.focusedIndex, 1);
    expect(c.blocks[1].html, '<p>X</p>');
    expect(c.blocks[2].html, '<p>B</p>');
  });

  test('move up/down keeps focus with the block and respects bounds', () {
    final c = EditorController(initialContent: _three);
    c.focus(2);
    c.move(2, 1); // already at bottom -> no-op
    expect(c.focusedIndex, 2);
    expect(c.blocks[2].html, '<p>C</p>');

    c.move(2, -1); // C moves up to index 1, focus follows
    expect(c.focusedIndex, 1);
    expect(c.blocks[0].html, '<p>A</p>');
    expect(c.blocks[1].html, '<p>C</p>');
    expect(c.blocks[2].html, '<p>B</p>');

    c.move(0, -1); // A at top moving up -> no-op
    expect(c.blocks.first.html, '<p>A</p>');
  });

  test('delete removes a block and adjusts focus', () {
    final c = EditorController(initialContent: _three);
    c.focus(2);
    c.delete(0); // delete A; focus 2 -> 1
    expect(c.blocks.length, 2);
    expect(c.focusedIndex, 1);
    expect(c.blocks.map((b) => b.html).toList(), ['<p>B</p>', '<p>C</p>']);

    c.delete(1); // delete C (focused) -> focus cleared
    expect(c.blocks.length, 1);
    expect(c.focusedIndex, isNull);
    expect(c.blocks.single.html, '<p>B</p>');
  });

  test('updateFromExternal is a no-op for an echo of emitted content', () {
    final c = EditorController(initialContent: '<p>One</p>');
    c.updateHtml(0, '<p>One edited</p>');
    final afterEdit = c.content;
    // Feed back the same serialized HTML: should NOT reparse/reset focus.
    c.updateFromExternal(afterEdit);
    expect(c.content, afterEdit);
    expect(c.focusedIndex, isNull);
  });

  test('updateFromExternal reparses a genuinely different external update', () {
    final c = EditorController(initialContent: '<p>One</p>');
    c.focus(0);
    c.updateFromExternal('<p>Brand</p>\n\n<p>New</p>');
    expect(c.blocks.length, 2);
    expect(c.focusedIndex, isNull); // focus reset on external load
    expect(c.content, contains('<p>Brand</p>'));
  });

  test('notifyListeners fires for each mutation (UI rebuild hook)', () {
    final c = EditorController(initialContent: _three);
    var notifications = 0;
    c.addListener(() => notifications++);
    c.updateHtml(0, '<p>Edited</p>');
    c.insert(_para('<p>Two</p>'));
    c.move(1, -1);
    c.delete(0);
    expect(notifications, 4);
  });
}
