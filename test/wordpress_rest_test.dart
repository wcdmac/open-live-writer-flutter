import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_live_writer/models/blog.dart';
import 'package:open_live_writer/models/blog_post.dart';
import 'package:open_live_writer/services/rest/wordpress_rest.dart';

/// Builds a [WordPressRestClient] wired to a [MockClient] so no real network
/// is touched. Each test uses a distinct base URL so the static status cache
/// (P-10/P-15) can't leak between cases.
WordPressRestClient _client(
  String base,
  MockClientHandler handler, {
  RestAuthMethod auth = RestAuthMethod.applicationPassword,
}) =>
    WordPressRestClient(
      baseUrl: base,
      username: 'u',
      password: 'p',
      authMethod: auth,
      httpClient: MockClient(handler),
    );

const _postJson = {
  'id': 1,
  'title': {'rendered': 'Hi'},
  'status': 'publish',
  'date_gmt': '2024-01-01T00:00:00',
  'excerpt': {'rendered': 'hello'},
  'link': 'https://example.com/hi',
};

void main() {
  group('WordPressRestClient', () {
    // ----------------------------------------------------------------- P-01
    test('newCategory throws typed error on empty body (P-01)', () async {
      final c = _client('https://a1.test/wp-json',
          (req) async => http.Response('', 201));
      expect(
        () => c.newCategory('Cat'),
        throwsA(isA<WordPressRestException>()),
      );
    });

    test('newCategory returns category on valid body', () async {
      final c = _client(
        'https://a2.test/wp-json',
        (req) async =>
            http.Response(jsonEncode({'id': 9, 'name': 'Cat', 'slug': 'cat'}), 201),
      );
      final cat = await c.newCategory('Cat');
      expect(cat.id, '9');
      expect(cat.name, 'Cat');
    });

    // ----------------------------------------------------------------- P-02
    test('uploadMedia throws typed error on empty body (P-02)', () async {
      final c = _client('https://a3.test/wp-json',
          (req) async => http.Response('', 200));
      expect(
        () => c.uploadMedia('a.png', [1, 2, 3], 'image/png'),
        throwsA(isA<WordPressRestException>()),
      );
    });

    test('uploadMedia parses source_url', () async {
      final c = _client(
        'https://a4.test/wp-json',
        (req) async => http.Response(
          jsonEncode({'id': 7, 'source_url': 'https://example.com/a.png'}),
          200,
        ),
      );
      final r = await c.uploadMedia('a.png', [1, 2, 3], 'image/png');
      expect(r.id, '7');
      expect(r.url, 'https://example.com/a.png');
    });

    // ----------------------------------------------------------------- P-03
    test('JWT: 401 clears token and retries the request once (P-03)', () async {
      var postsCalls = 0;
      final c = _client(
        'https://a5.test/wp-json',
        (http.Request req) async {
          if (req.url.path.contains('jwt-auth')) {
            return http.Response(jsonEncode({'token': 'T'}), 200);
          }
          postsCalls++;
          if (postsCalls == 1) return http.Response('', 401);
          return http.Response(jsonEncode([_postJson]), 200);
        },
        auth: RestAuthMethod.jwt,
      );
      final posts = await c.getPosts();
      expect(posts.length, 1);
      expect(postsCalls, 2, reason: 'request should have been retried once');
    });

    test('JWT: 403 also clears token and retries (P-03)', () async {
      var postsCalls = 0;
      final c = _client(
        'https://a6.test/wp-json',
        (http.Request req) async {
          if (req.url.path.contains('jwt-auth')) {
            return http.Response(jsonEncode({'token': 'T'}), 200);
          }
          postsCalls++;
          if (postsCalls == 1) {
            return http.Response(jsonEncode({'code': 'jwt_invalid', 'message': 'x'}),
                403);
          }
          return http.Response(jsonEncode([_postJson]), 200);
        },
        auth: RestAuthMethod.jwt,
      );
      final posts = await c.getPosts();
      expect(posts.length, 1);
      expect(postsCalls, 2);
    });

    // ----------------------------------------------------------------- P-08
    test('rejects oversized GET response before buffering (P-08)', () async {
      final big = 'x' * (17 * 1024 * 1024); // > 16 MiB cap
      final c = _client(
        'https://a7.test/wp-json',
        (req) async => http.Response(big, 200),
      );
      expect(() => c.getPosts(), throwsA(isA<WordPressRestException>()));
    });

    // ----------------------------------------------------------------- P-09
    test('getPosts sends _fields projection when requested (P-09)', () async {
      String? captured;
      final c = _client(
        'https://a8.test/wp-json',
        (req) async {
          captured = req.url.query;
          return http.Response(jsonEncode([]), 200);
        },
      );
      await c.getPosts(fields: const ['id', 'title', 'excerpt']);
      // query parameters are percent-encoded (commas → %2C), so decode.
      expect(Uri.decodeQueryComponent(captured!),
          contains('_fields=id,title,excerpt'));
    });

    test('getPosts omits _fields by default (P-09)', () async {
      String? captured;
      final c = _client(
        'https://a9.test/wp-json',
        (req) async {
          captured = req.url.query;
          return http.Response(jsonEncode([_postJson]), 200);
        },
      );
      await c.getPosts();
      expect(captured, isNot(contains('_fields')));
    });

    // ----------------------------------------------------------------- P-10 / P-15
    test('getPosts degrades when "private" status is forbidden (P-10)',
        () async {
      var calls = 0;
      final c = _client(
        'https://a10.test/wp-json',
        (req) async {
          calls++;
          final status = req.url.queryParameters['status'] ?? '';
          if (status.contains('private')) {
            return http.Response(
              jsonEncode({'code': 'rest_forbidden', 'message': 'no'}),
              403,
            );
          }
          return http.Response(jsonEncode([]), 200);
        },
      );
      final posts = await c.getPosts();
      expect(posts, isEmpty);
      // Must have walked past the private-containing tier(s).
      expect(calls, greaterThan(1));
    });

    test('getPosts caches accepted query per endpoint (P-10/P-15)', () async {
      var calls = 0;
      final c = _client(
        'https://a11.test/wp-json',
        (req) async {
          calls++;
          final status = req.url.queryParameters['status'] ?? '';
          // Only the "publish,draft,pending" tier is accepted.
          if (status != 'publish,draft,pending') {
            return http.Response(
              jsonEncode({'code': 'rest_forbidden', 'message': 'no'}),
              403,
            );
          }
          return http.Response(jsonEncode([]), 200);
        },
      );
      await c.getPosts();
      final callsAfterFirst = calls;
      await c.getPosts(); // cached → single retry of the accepted query
      expect(calls, callsAfterFirst + 1,
          reason: 'second call should reuse the cached query, not re-walk');
    });

    test('getPosts keeps posts and pages caches separate (P-15)', () async {
      final seen = <String>{};
      final c = _client(
        'https://a12.test/wp-json',
        (req) async {
          seen.add(req.url.path);
          final status = req.url.queryParameters['status'] ?? '';
          final isPages = req.url.path.endsWith('/pages');
          // pages endpoint rejects any query containing 'private'; posts
          // accept everything — so the two caches must be independent.
          if (isPages && status.contains('private')) {
            return http.Response(
              jsonEncode({'code': 'rest_forbidden', 'message': 'no'}),
              403,
            );
          }
          return http.Response(jsonEncode([]), 200);
        },
      );
      await c.getPosts(pages: true); // walks the chain, ends on 'publish'
      await c.getPosts(); // posts: cached-free, should probe (not reuse pages cache)
      expect(seen.contains('/wp-json/wp/v2/posts'), isTrue,
          reason: 'posts fetch must run independently of the pages cache');
    });

    // ----------------------------------------------------------------- P3-14
    test('newPost sends SEO meta when set (P3-14)', () async {
      Map<String, dynamic>? body;
      final c = _client(
        'https://a13.test/wp-json',
        (req) async {
          if (req.method == 'POST' && req.url.path.contains('/posts')) {
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'id': 99, 'status': 'draft'}), 200);
          }
          return http.Response(jsonEncode([]), 200);
        },
      );
      await c.newPost(
        BlogPost(
          title: 'T',
          content: 'C',
          seoTitle: 'My Title',
          seoDescription: 'My Desc',
          ogImageUrl: 'https://x/y.png',
        ),
        publish: false,
      );
      expect(body, isNotNull);
      final meta = body!['meta'] as Map<String, dynamic>;
      expect(meta['_yoast_wpseo_title'], 'My Title');
      expect(meta['_yoast_wpseo_metadesc'], 'My Desc');
      expect(meta['_yoast_wpseo_opengraph-image'], 'https://x/y.png');
    });

    test('newPost omits meta when SEO fields empty (P3-14)', () async {
      Map<String, dynamic>? body;
      final c = _client(
        'https://a14.test/wp-json',
        (req) async {
          if (req.method == 'POST' && req.url.path.contains('/posts')) {
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'id': 1, 'status': 'draft'}), 200);
          }
          return http.Response(jsonEncode([]), 200);
        },
      );
      await c.newPost(BlogPost(title: 'T', content: 'C'), publish: false);
      expect(body!.containsKey('meta'), isFalse);
    });

    test('getPost reads SEO meta back (P3-14)', () async {
      final c = _client(
        'https://a15.test/wp-json',
        (req) async => http.Response(
          jsonEncode({
            'id': 1,
            'title': {'rendered': 'Hi'},
            'status': 'publish',
            'date_gmt': '2024-01-01T00:00:00',
            'meta': {
              '_yoast_wpseo_title': 'SEO',
              '_yoast_wpseo_metadesc': 'DESC',
              '_yoast_wpseo_opengraph-image': 'https://x/y.png',
            },
          }),
          200,
        ),
      );
      final post = await c.getPost('1');
      expect(post.seoTitle, 'SEO');
      expect(post.seoDescription, 'DESC');
      expect(post.ogImageUrl, 'https://x/y.png');
    });

    // ----------------------------------------------------------------- P3-14 (multi-author)
    test('newPost sends author when set (P3-14)', () async {
      Map<String, dynamic>? body;
      final c = _client(
        'https://a16.test/wp-json',
        (req) async {
          if (req.method == 'POST' && req.url.path.contains('/posts')) {
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'id': 1, 'status': 'draft'}), 200);
          }
          return http.Response(jsonEncode([]), 200);
        },
      );
      await c.newPost(
        BlogPost(title: 'T', content: 'C', authorId: '7', authorName: 'Bob'),
        publish: false,
      );
      expect(body!['author'], '7');
    });

    test('newPost omits author when empty (P3-14)', () async {
      Map<String, dynamic>? body;
      final c = _client(
        'https://a17.test/wp-json',
        (req) async {
          if (req.method == 'POST' && req.url.path.contains('/posts')) {
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'id': 1, 'status': 'draft'}), 200);
          }
          return http.Response(jsonEncode([]), 200);
        },
      );
      await c.newPost(BlogPost(title: 'T', content: 'C'), publish: false);
      expect(body!.containsKey('author'), isFalse);
    });

    test('getPost reads author back (P3-14)', () async {
      final c = _client(
        'https://a18.test/wp-json',
        (req) async => http.Response(
          jsonEncode({
            'id': 1,
            'title': {'rendered': 'Hi'},
            'status': 'publish',
            'date_gmt': '2024-01-01T00:00:00',
            'author': 7,
          }),
          200,
        ),
      );
      final post = await c.getPost('1');
      expect(post.authorId, '7');
    });
  });
}
