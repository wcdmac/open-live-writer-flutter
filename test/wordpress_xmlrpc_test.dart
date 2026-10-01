import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

void main() {
  group('WordPressXmlRpcClient (L2)', () {
    test('uploadMedia throws StateError on non-struct response (L2)', () {
      final c = _client((req) async => http.Response(_scalarResponse, 200));
      expect(
        () => c.uploadMedia('a.png', [1, 2, 3], 'image/png'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
