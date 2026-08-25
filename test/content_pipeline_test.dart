import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_live_writer/models/blog.dart';
import 'package:open_live_writer/models/blog_post.dart';
import 'package:open_live_writer/services/rest/wordpress_rest.dart';
import 'package:open_live_writer/services/xmlrpc/wordpress_xmlrpc.dart';
import 'package:open_live_writer/services/xmlrpc/xmlrpc_client.dart';

/// End-to-end parsing tests for the post content pipeline — the chain
/// that was blamed for "post opens but content never shows".
void main() {
  group('REST content parsing', () {
    WordPressRestClient clientFor(http.Client mock) => WordPressRestClient(
          baseUrl: 'https://example.com/wp-json',
          username: 'user',
          password: 'pwd xyz',
          httpClient: mock,
        );

    test('getPost prefers content.raw (edit context)', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'GET');
        // GET must not carry a body (WAF compatibility).
        expect(req.bodyBytes, isEmpty);
        expect(
            req.url.toString(),
            contains(
                'https://example.com/wp-json/wp/v2/posts/7?context=edit'));
        return http.Response(
          jsonEncode({
            'id': 7,
            'status': 'draft',
            'title': {'raw': 'Hello', 'rendered': 'Hello'},
            'content': {
              'raw': '<p>Full <strong>raw</strong> body</p>',
              'rendered': '<p>rendered</p>',
            },
            'categories': [3],
            'tags': [9],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final post = await clientFor(mock).getPost('7');
      expect(post.id, '7');
      expect(post.title, 'Hello');
      expect(post.content, contains('<strong>raw</strong>'));
      expect(post.status, PostStatus.draft);
    });

    test('getPost falls back to rendered when raw is empty string',
        () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({
              'id': 8,
              'status': 'publish',
              'title': {'raw': 'T', 'rendered': 'T'},
              'content': {'raw': '', 'rendered': '<p>Rendered only</p>'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final post = await clientFor(mock).getPost('8');
      // The bug: empty-string raw used to win over rendered.
      expect(post.content, '<p>Rendered only</p>');
    });

    test('getPosts requests all editable statuses (drafts included)',
        () async {
      Uri? seen;
      final mock = MockClient((req) async {
        seen = req.url;
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'status': 'draft',
              'title': {'raw': 'Draft'},
              'content': {'raw': '<p>d</p>', 'rendered': '<p>d</p>'},
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final posts = await clientFor(mock).getPosts(perPage: 10);
      expect(posts, hasLength(1));
      expect(posts.first.status, PostStatus.draft);
      expect(posts.first.content, '<p>d</p>');
      expect(seen!.query, contains('draft'));
      expect(seen!.query, contains('status'));
    });

    test('getPosts degrades to publish when multi-status is forbidden',
        () async {
      final requestedStatuses = <String>[];
      final mock = MockClient((req) async {
        final statuses = req.url.queryParameters['status'] ?? '';
        requestedStatuses.add(statuses);
        if (statuses.contains('private') || statuses.contains('future')) {
          // Role without permission for private/future: whole request fails.
          return http.Response(
            jsonEncode({
              'code': 'rest_forbidden_status',
              'message': 'Status is forbidden.',
              'data': {'status': 401},
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([
            {
              'id': 2,
              'status': 'publish',
              'title': {'raw': 'Public'},
              'content': {'raw': '<p>body</p>', 'rendered': '<p>body</p>'},
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final posts = await clientFor(mock).getPosts(perPage: 10);
      expect(posts, hasLength(1));
      expect(posts.first.title, 'Public');
      // Degradation chain: full set rejected, reduced set succeeded.
      expect(requestedStatuses.length, 2);
      expect(requestedStatuses.first, contains('private'));
      expect(requestedStatuses.last, 'publish,draft,pending');
    });

    test('getPost falls back to context=view on 401 (rendered content)',
        () async {
      final contexts = <String>[];
      final mock = MockClient((req) async {
        final ctx = req.url.queryParameters['context'] ?? '';
        contexts.add(ctx);
        if (ctx == 'edit') {
          return http.Response(
            jsonEncode({
              'code': 'rest_forbidden_context',
              'message': 'Sorry, you are not allowed to edit this post.',
              'data': {'status': 401},
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'id': 12,
            'status': 'publish',
            'title': {'rendered': 'View only'},
            'content': {'rendered': '<p>Rendered body</p>'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final post = await clientFor(mock).getPost('12');
      expect(contexts, ['edit', 'view']);
      expect(post.title, 'View only');
      expect(post.content, '<p>Rendered body</p>');
    });

    test('JSON REST error payload is surfaced with status code', () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({
              'code': 'rest_forbidden_context',
              'message': 'Sorry, you are not allowed to edit this post.',
            }),
            401,
            headers: {'content-type': 'application/json'},
          ));
      try {
        await clientFor(mock).getPost('9');
        fail('should have thrown');
      } on WordPressRestException catch (e) {
        expect(e.statusCode, 401);
        expect(e.code, 'rest_forbidden_context');
      }
    });
  });

  group('XML-RPC content parsing', () {
    WordPressXmlRpcClient clientFor(MockClientHandler handler) {
      final client = XmlRpcClient(
        endpoint: Uri.parse('https://example.com/xmlrpc.php'),
        username: 'user',
        password: 'pwd',
        httpClient: MockClient(handler),
      );
      return WordPressXmlRpcClient(client, flavor: XmlRpcFlavor.wordpress)
        ..blogId = '1';
    }

    test('wp.getPost parses post_content', () async {
      final wp = clientFor((req) async {
        expect(req.url.toString(), 'https://example.com/xmlrpc.php');
        final body = utf8.decode(req.bodyBytes);
        expect(body, contains('wp.getPost'));
        return http.Response(
          '''
<?xml version="1.0"?>
<methodResponse><params><param><value><struct>
  <member><name>post_id</name><value><int>5</int></value></member>
  <member><name>post_title</name><value><string>My draft</string></value></member>
  <member><name>post_content</name><value><string>&lt;p&gt;Hello &amp;amp; world&lt;/p&gt;</string></value></member>
  <member><name>post_status</name><value><string>draft</string></value></member>
  <member><name>post_date_gmt</name><value><dateTime.iso8601>20260820T10:00:00</dateTime.iso8601></value></member>
</struct></value></param></params></methodResponse>
''',
          200,
        );
      });
      final post = await wp.getPost('5');
      expect(post.id, '5');
      expect(post.title, 'My draft');
      expect(post.content, '<p>Hello &amp; world</p>');
      expect(post.status, PostStatus.draft);
    });

    test('metaWeblog.getPost fallback parses description', () async {
      final wp = clientFor((req) async {
        final body = utf8.decode(req.bodyBytes);
        if (body.contains('wp.getPost')) {
          // Server without wp.getPost: classic method-missing fault 405.
          return http.Response(
            '''
<?xml version="1.0"?>
<methodResponse><fault><value><struct>
  <member><name>faultCode</name><value><int>405</int></value></member>
  <member><name>faultString</name><value><string>Invalid server method</string></value></member>
</struct></value></fault></methodResponse>
''',
            200,
          );
        }
        return http.Response(
          '''
<?xml version="1.0"?>
<methodResponse><params><param><value><struct>
  <member><name>postid</name><value><string>11</string></value></member>
  <member><name>title</name><value><string>Fallback title</string></value></member>
  <member><name>description</name><value><string>&lt;p&gt;MetaWeblog body&lt;/p&gt;</string></value></member>
  <member><name>dateCreated</name><value><dateTime.iso8601>20260821T08:30:00</dateTime.iso8601></value></member>
</struct></value></param></params></methodResponse>
''',
          200,
        );
      });
      final post = await wp.getPost('11');
      expect(post.id, '11');
      expect(post.title, 'Fallback title');
      expect(post.content, '<p>MetaWeblog body</p>');
    });

    test('wp.getPosts list parses content for drafts', () async {
      final wp = clientFor((req) async {
        final body = utf8.decode(req.bodyBytes);
        expect(body, contains('wp.getPosts'));
        // post_status filter must ask for drafts (array or string).
        expect(body, contains('draft'));
        return http.Response(
          '''
<?xml version="1.0"?>
<methodResponse><params><param><value><array><data>
<value><struct>
  <member><name>post_id</name><value><int>21</int></value></member>
  <member><name>post_title</name><value><string>List draft</string></value></member>
  <member><name>post_content</name><value><string>&lt;p&gt;List body&lt;/p&gt;</string></value></member>
  <member><name>post_status</name><value><string>draft</string></value></member>
</struct></value>
</data></array></value></param></params></methodResponse>
''',
          200,
        );
      });
      final posts = await wp.getPosts(count: 10);
      expect(posts, hasLength(1));
      expect(posts.first.content, '<p>List body</p>');
      expect(posts.first.status, PostStatus.draft);
    });
  });
}

typedef MockClientHandler = Future<http.Response> Function(http.Request req);
