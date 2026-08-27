import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/models/blog_post.dart';
import 'package:open_live_writer/services/local_draft_store.dart';
import 'package:open_live_writer/services/post_exporter.dart';

void main() {
  group('LocalDraft offline copy', () {
    test('JSON round-trip preserves offline-copy metadata', () {
      final draft = LocalDraft(
        id: 'd1',
        accountId: 'a1',
        title: 'Hello',
        content: '<p>World</p>',
        updatedAt: DateTime(2026, 8, 26, 12, 0),
        postId: '42',
        postStatus: 'publish',
        isPage: false,
        categories: ['3', '5'],
        tags: ['flutter', 'wordpress'],
        remoteModified: DateTime(2026, 8, 25),
      );
      final restored = LocalDraft.fromJson(draft.toJson());

      expect(restored.postId, '42');
      expect(restored.isOfflineCopy, isTrue);
      expect(restored.postStatus, 'publish');
      expect(restored.categories, ['3', '5']);
      expect(restored.tags, ['flutter', 'wordpress']);
      expect(restored.remoteModified, DateTime(2026, 8, 25));
    });

    test('toBlogPost keeps server id so saves edit instead of duplicate', () {
      final draft = LocalDraft(
        id: 'd1',
        accountId: 'a1',
        title: 'T',
        content: 'C',
        updatedAt: DateTime.now(),
        postId: '42',
        postStatus: 'publish',
      );
      final post = draft.toBlogPost();
      expect(post.isNew, isFalse, reason: 'offline copy must not be "new"');
      expect(post.id, '42');
      expect(post.status, PostStatus.publish);
    });

    test('plain draft (no postId) is not an offline copy', () {
      final draft = LocalDraft(
        id: 'd2',
        accountId: 'a1',
        title: 'T',
        content: 'C',
        updatedAt: DateTime.now(),
      );
      expect(draft.isOfflineCopy, isFalse);
      expect(draft.toJson()['postId'], isNull);
    });
  });

  group('PostExporter', () {
    final post = BlogPost(
      id: '7',
      title: 'Title <b>bold</b>',
      content: '<h2>Head</h2><p>Some <strong>bold</strong> text.</p>',
      slug: 'title-slug',
      status: PostStatus.publish,
      datePublished: DateTime(2026, 8, 1),
      categories: ['3'],
      tags: ['wp'],
    );

    test('HTML document escapes the title and keeps block markup', () {
      final doc = PostExporter.buildHtmlDocument(post);
      expect(doc, contains('<title>Title &lt;b&gt;bold&lt;/b&gt;</title>'));
      expect(doc, contains(post.content));
      expect(doc.startsWith('<!DOCTYPE html>'), isTrue);
    });

    test('Markdown conversion emits front matter and body', () {
      final md = PostExporter.toMarkdown(post);
      expect(md, startsWith('---\n'));
      expect(md, contains('title: "Title <b>bold</b>"'));
      expect(md, contains('status: publish'));
      expect(md, contains('categories: ["3"]'));
      expect(md, contains('## Head'));
      expect(md, contains('**bold**'));
    });

    test('safeName strips path separators and keeps CJK titles', () {
      final name = PostExporter.safeName('测试也/a:b*c?"<>|');
      expect(name, isNot(contains(RegExp(r'[\\/:*?"<>|]'))));
      expect(PostExporter.safeName('测试也-32'), '测试也-32');
    });
  });
}
