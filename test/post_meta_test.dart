import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/models/blog_post.dart';
import 'package:open_live_writer/services/post_meta.dart';

void main() {
  group('buildPostMeta / buildXmlRpcPostMeta', () {
    test('empty post produces an empty meta map', () {
      expect(buildPostMeta(BlogPost()), isEmpty);
      expect(buildXmlRpcPostMeta(BlogPost()), isEmpty);
    });

    test('only non-empty fields are included', () {
      final post = BlogPost(
        seoTitle: '  ', // whitespace-only → treated as empty
        seoDescription: 'A great post about widgets.',
      );
      final meta = buildPostMeta(post);
      expect(meta.containsKey(PostMetaKeys.seoTitle), isFalse);
      expect(meta[PostMetaKeys.seoDescription], 'A great post about widgets.');
      expect(meta.length, 1);
    });

    test('all three fields are emitted and trimmed', () {
      final post = BlogPost(
        seoTitle: '  My SEO Title  ',
        seoDescription: 'Desc',
        ogImageUrl: 'https://example.com/og.png',
      );
      final meta = buildPostMeta(post);
      expect(meta[PostMetaKeys.seoTitle], 'My SEO Title');
      expect(meta[PostMetaKeys.seoDescription], 'Desc');
      expect(meta[PostMetaKeys.ogImage], 'https://example.com/og.png');
    });

    test('XML-RPC meta is a key/value list', () {
      final post = BlogPost(
        seoTitle: 'T',
        seoDescription: 'D',
        ogImageUrl: 'https://example.com/og.png',
      );
      final list = buildXmlRpcPostMeta(post);
      expect(list, hasLength(3));
      expect(list.first, {'key': PostMetaKeys.seoTitle, 'value': 'T'});
      expect(list.last, {
        'key': PostMetaKeys.ogImage,
        'value': 'https://example.com/og.png',
      });
    });

    test('copy() preserves SEO fields', () {
      final post = BlogPost(
        seoTitle: 'T',
        seoDescription: 'D',
        ogImageUrl: 'https://example.com/og.png',
      );
      final c = post.copy();
      expect(c.seoTitle, 'T');
      expect(c.seoDescription, 'D');
      expect(c.ogImageUrl, 'https://example.com/og.png');
    });
  });

  group('readRestMeta / readXmlRpcMeta', () {
    test('reads a Yoast key from a REST meta map', () {
      final meta = {
        PostMetaKeys.seoTitle: 'REST Title',
        PostMetaKeys.seoDescription: 'REST Desc',
      };
      expect(readRestMeta(meta, PostMetaKeys.seoTitle), 'REST Title');
      expect(readRestMeta(meta, PostMetaKeys.seoDescription), 'REST Desc');
      expect(readRestMeta(meta, PostMetaKeys.ogImage), isNull);
      expect(readRestMeta(null, PostMetaKeys.seoTitle), isNull);
    });

    test('reads a Yoast key from an XML-RPC post_meta list', () {
      final postMeta = [
        {'key': PostMetaKeys.seoTitle, 'value': 'XML Title', 'id': '5'},
        {'key': PostMetaKeys.ogImage, 'value': 'https://x/y.png'},
      ];
      expect(readXmlRpcMeta(postMeta, PostMetaKeys.seoTitle), 'XML Title');
      expect(readXmlRpcMeta(postMeta, PostMetaKeys.ogImage),
          'https://x/y.png');
      expect(readXmlRpcMeta(postMeta, PostMetaKeys.seoDescription), isNull);
      expect(readXmlRpcMeta(null, PostMetaKeys.seoTitle), isNull);
    });
  });
}
