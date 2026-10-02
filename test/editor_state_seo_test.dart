import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/models/blog_post.dart';
import 'package:open_live_writer/state/editor_state.dart';

void main() {
  group('EditorState SEO metadata (P3-14)', () {
    test('updateSeo sets all three fields and marks dirty', () {
      final editor = EditorState();
      var notified = 0;
      editor.addListener(() => notified++);
      editor.updateSeo(
        seoTitle: 'T',
        seoDescription: 'D',
        ogImageUrl: 'https://x/y.png',
      );
      expect(editor.post.seoTitle, 'T');
      expect(editor.post.seoDescription, 'D');
      expect(editor.post.ogImageUrl, 'https://x/y.png');
      expect(editor.isDirty, isTrue);
      expect(notified, 1);
    });

    test('updateSeo only touches the fields supplied', () {
      final editor = EditorState();
      editor.updateSeo(seoTitle: 'T', ogImageUrl: 'https://x/y.png');
      editor.updateSeo(seoDescription: 'D');
      expect(editor.post.seoTitle, 'T', reason: 'untouched field preserved');
      expect(editor.post.ogImageUrl, 'https://x/y.png');
      expect(editor.post.seoDescription, 'D');
    });

    test('updateSeo trims and clears whitespace-only values', () {
      final editor = EditorState();
      editor.updateSeo(seoTitle: '  My Title  ', seoDescription: '   ');
      expect(editor.post.seoTitle, 'My Title');
      expect(editor.post.seoDescription, isNull);
    });

    test('applyPost keeps local SEO when the server omits it', () {
      final editor = EditorState();
      editor.updateSeo(
        seoTitle: 'Keep',
        seoDescription: 'Keep desc',
        ogImageUrl: 'https://x/keep.png',
      );
      editor.applyPost(BlogPost(
        id: '7',
        title: 'Server title',
        content: 'Server content',
      ));
      expect(editor.post.title, 'Server title');
      expect(editor.post.seoTitle, 'Keep',
          reason: 'a server copy without meta must not wipe local SEO');
      expect(editor.post.seoDescription, 'Keep desc');
      expect(editor.post.ogImageUrl, 'https://x/keep.png');
    });

    test('applyPost takes SEO values the server provides', () {
      final editor = EditorState();
      editor.applyPost(BlogPost(
        id: '7',
        title: 'T',
        content: 'C',
        seoTitle: 'Server SEO',
        seoDescription: 'Server desc',
        ogImageUrl: 'https://x/server.png',
      ));
      expect(editor.post.seoTitle, 'Server SEO');
      expect(editor.post.seoDescription, 'Server desc');
      expect(editor.post.ogImageUrl, 'https://x/server.png');
    });
  });
}
