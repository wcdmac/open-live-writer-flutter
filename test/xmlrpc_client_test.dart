import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_live_writer/services/xmlrpc/xmlrpc_client.dart';
import 'package:open_live_writer/services/xmlrpc/xmlrpc_codec.dart';

XmlRpcClient _client(MockClientHandler handler) => XmlRpcClient(
      endpoint: Uri.parse('https://example.com/xmlrpc.php'),
      username: 'u',
      password: 'p',
      httpClient: MockClient(handler),
    );

void main() {
  group('XmlRpcClient', () {
    // ----------------------------------------------------------------- P-07
    test('rejects oversized response before buffering (P-07)', () {
      final big = '<methodResponse><params><param><value>'
          '<string>${'x' * (17 * 1024 * 1024)}</string></value></param>'
          '</params></methodResponse>';
      final c = _client((req) async => http.Response(big, 200));
      expect(
        () => c.callMethod('demo.sayHello', []),
        throwsA(isA<XmlRpcFault>()),
      );
    });

    test('surfaces HTTP error status as XmlRpcFault', () {
      final c = _client((req) async => http.Response('server error', 500));
      expect(
        () => c.callMethod('demo.sayHello', []),
        throwsA(isA<XmlRpcFault>()),
      );
    });

    test('decodes a normal response', () {
      const xml = '<?xml version="1.0"?><methodResponse><params>'
          '<param><value><string>hello</string></value></param>'
          '</params></methodResponse>';
      final c = _client((req) async => http.Response(xml, 200));
      expect(c.callMethod('demo.sayHello', []), completion('hello'));
    });
  });
}
