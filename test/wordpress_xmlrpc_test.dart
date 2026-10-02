import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_live_writer/models/blog_post.dart';
import 'package:open_live_writer/services/xmlrpc/xmlrpc_client.dart';
import 'package:open_live_writer/services/xmlrpc/wordpress_xmlrpc.dart';

WordPressXmlRpcClient _client(MockClientHandler handler) {
  final xml = XmlRpcClient(
    endpoint: Uri.parse('https://example.com/xmlrpc.php'),
    username: 'u',
    password: 'p',
    httpClient: MockClient(handler),
  );
  final client = WordPressXmlRpcClient(xml);
  client.blogId = '1';
  return client;
}

// A malformed but well-formed XML-RPC response: both methods return a scalar
// string instead of the documented struct. This used to throw an opaque
// CastError at `result as Map` (L2); it should now surface a typed StateError.
const _scalarResponse = '<?xml version="1.0"?><methodResponse><params>'
    '<param><value><string>unexpected</string></value></param>'
    '</params></methodResponse>';

/// Captures the params passed to `wp.newPost` so the SEO `post_meta` struct
/// can be inspected without decoding XML.
class _CaptureXmlRpcClient extends XmlRpcClient {
  _CaptureXmlRpcClient()
      : super(
          endpoint: Uri.parse('https://example.com/xmlrpc.php'),
          username: 'u',
          password: 'p',
          httpClient: MockClient((_) async => http.Response('', 200)),
        );

  List<dynamic>? newPostParams;
  Map<String, dynamic>? getPostOverride;

  @override
  Future<dynamic> callMethod(
    String methodName,
    List<dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (methodName == 'wp.newPost') {
      newPostParams = params;
      return '123';
    }
    if (methodName == 'wp.getPost' && getPostOverride != null) {
      return getPostOverride;
    }
    // getTags / getPost fallbacks — return an empty, accepted payload.
    return const <dynamic>[];
  }
}

WordPressXmlRpcClient _captureClient(_CaptureXmlRpcClient fake) {
  final client = WordPressXmlRpcClient(fake);
  client.blogId = '1';
  return client;
}

void main() {
  group('WordPressXmlRpcClient (L2)', () {
    test('uploadMedia throws StateError on non-struct response (L2)', () {
      final c = _client((req) async => http.Response(_scalarResponse, 200));
      expect(
        () => c.uploadMedia('a.png', [1, 2, 3], 'image/png'),
        throwsA(isA<StateError>()),
      );
    });

    // --------------------------------------------------------------- P3-14
    test('newPost sends SEO post_meta when set (P3-14)', () async {
      final fake = _CaptureXmlRpcClient();
      final c = _captureClient(fake);
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
      final content = fake.newPostParams![3] as Map<String, dynamic>;
      final meta = content['post_meta'] as List<Map<String, String>>;
      expect(meta, contains({'key': '_yoast_wpseo_title', 'value': 'My Title'}));
      expect(meta, contains({'key': '_yoast_wpseo_metadesc', 'value': 'My Desc'}));
      expect(meta,
          contains({'key': '_yoast_wpseo_opengraph-image', 'value': 'https://x/y.png'}));
    });

    test('newPost omits post_meta when SEO fields empty (P3-14)', () async {
      final fake = _CaptureXmlRpcClient();
      final c = _captureClient(fake);
      await c.newPost(BlogPost(title: 'T', content: 'C'), publish: false);
      final content = fake.newPostParams![3] as Map<String, dynamic>;
      expect(content.containsKey('post_meta'), isFalse);
    });

    test('getPost reads SEO post_meta back (P3-14)', () async {
      final fake = _CaptureXmlRpcClient()
        ..getPostOverride = {
          'post_id': 1,
          'post_title': 'Hi',
          'post_status': 'publish',
          'post_meta': [
            {'key': '_yoast_wpseo_title', 'value': 'SEO'},
            {'key': '_yoast_wpseo_metadesc', 'value': 'DESC'},
            {'key': '_yoast_wpseo_opengraph-image', 'value': 'https://x/y.png'},
          ],
        };
      final c = _captureClient(fake);
      final post = await c.getPost('1');
      expect(post.seoTitle, 'SEO');
      expect(post.seoDescription, 'DESC');
      expect(post.ogImageUrl, 'https://x/y.png');
    });
  });
}

