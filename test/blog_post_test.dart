import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/models/blog_post.dart';

void main() {
  group('BlogPost.displayExcerpt (L1)', () {
    test('strips HTML tags from rendered excerpt (excerpt.rendered)', () {
      // REST list responses expose `excerpt.rendered`, which wraps the text in
      // <p>…</p>. The dashboard tile uses Text(), so tags must not leak through.
      final p = BlogPost(excerpt: '<p>Hello <b>world</b> this is a post.</p>\n');
      expect(p.displayExcerpt, 'Hello world this is a post.');
    });

    test('returns plain text unchanged when excerpt has no tags', () {
      final p = BlogPost(excerpt: 'Just a summary.');
      expect(p.displayExcerpt, 'Just a summary.');
    });

    test('falls back to plain-text content when excerpt is empty', () {
      final p = BlogPost(
        content: '<p>First paragraph.</p>\n<p>Second paragraph.</p>',
      );
      final e = p.displayExcerpt;
      expect(e, isNot(contains('<')));
      expect(e, 'First paragraph. Second paragraph.');
    });

    test('caps content-derived fallback at 160 chars + ellipsis', () {
      final p = BlogPost(content: 'word ' * 100);
      final e = p.displayExcerpt;
      expect(e.endsWith('…'), isTrue);
      expect(e.length, 161);
    });
  });
}
