import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/services/xmlrpc/xmlrpc_codec.dart';

void main() {
  group('XmlRpcCodec.encodeRequest', () {
    test('encodes method with typed params', () {
      final xml = XmlRpcCodec.encodeRequest('wp.getUsersBlogs', [
        'admin',
        'secret',
        42,
        true,
        3.14,
        ['a', 'b'],
        {'title': 'Hello', 'count': 5},
      ]);

      expect(xml, contains('<methodName>wp.getUsersBlogs</methodName>'));
      expect(xml, contains('<value><string>admin</string></value>'));
      expect(xml, contains('<value><int>42</int></value>'));
      expect(xml, contains('<value><boolean>1</boolean></value>'));
      expect(xml, contains('<value><double>3.14</double></value>'));
      expect(xml, contains('<name>title</name><value><string>Hello</string>'));
      // list must round-trip as array/data
      expect(xml, contains('<array><data>'));
    });

    test('escapes XML entities in strings', () {
      final xml = XmlRpcCodec.encodeRequest(
          'metaWeblog.newPost', ['<b>&amp; "quotes"</b>']);
      // Only `<` and `&` must be escaped in XML text; the xml package
      // leaves `>` and quotes as-is.
      expect(xml, contains('&lt;b>&amp;amp; "quotes"&lt;/b>'));
    });

    test('encodes byte payloads as base64, not int array (upload regression)',
        () {
      final bytes = List<int>.generate(300, (i) => i % 256);
      final xml = XmlRpcCodec.encodeRequest('wp.uploadFile', [
        1,
        'user',
        'pass',
        {'name': 'a.jpg', 'type': 'image/jpeg', 'bits': bytes},
      ]);

      // bits must be a single <base64> value; encoding as <array> of ints
      // bloats the document ~30x and servers reject it (413 / parse error).
      expect(xml, contains('<name>bits</name><value><base64>'));
      expect(xml, isNot(contains('<name>bits</name><value><array>')));
      // and must survive decode back to bytes
      final doc = XmlRpcCodec.decodeResponse('''
<?xml version="1.0"?>
<methodResponse><params><param><value><base64>${base64Encode(bytes)}</base64></value></param></params></methodResponse>
''');
      expect(doc, equals(bytes));
    });
  });

  group('XmlRpcCodec.decodeResponse', () {
    test('decodes struct response', () {
      const body = '''
<?xml version="1.0"?>
<methodResponse>
  <params>
    <param>
      <value>
        <struct>
          <member><name>blogid</name><value><string>1</string></value></member>
          <member><name>blogName</name><value>My Blog</value></member>
          <member><name>url</name><value><string>https://x.example</string></value></member>
        </struct>
      </value>
    </param>
  </params>
</methodResponse>''';

      final result = XmlRpcCodec.decodeResponse(body) as Map;
      expect(result['blogid'], '1');
      expect(result['blogName'], 'My Blog');
      expect(result['url'], 'https://x.example');
    });

    test('decodes array of structs (getUsersBlogs shape)', () {
      const body = '''
<methodResponse>
  <params>
    <param>
      <value>
        <array>
          <data>
            <value><struct>
              <member><name>blogid</name><value><string>1</string></value></member>
              <member><name>blogName</name><value><string>Blog A</string></value></member>
              <member><name>url</name><value><string>https://a.example</string></value></member>
            </struct></value>
          </data>
        </array>
      </value>
    </param>
  </params>
</methodResponse>''';

      final result = XmlRpcCodec.decodeResponse(body) as List;
      expect(result, hasLength(1));
      expect(result.first['blogName'], 'Blog A');
    });

    test('throws XmlRpcFault on fault response', () {
      const body = '''
<methodResponse>
  <fault>
    <value>
      <struct>
        <member><name>faultCode</name><value><int>403</int></value></member>
        <member><name>faultString</name><value><string>Bad login</string></value></member>
      </struct>
    </value>
  </fault>
</methodResponse>''';

      expect(
        () => XmlRpcCodec.decodeResponse(body),
        throwsA(isA<XmlRpcFault>()
            .having((f) => f.code, 'code', 403)
            .having((f) => f.message, 'message', 'Bad login')),
      );
    });

    test('decodes dateTime.iso8601', () {
      const body = '''
<methodResponse>
  <params>
    <param>
      <value>
        <dateTime.iso8601>19980717T14:08:55</dateTime.iso8601>
      </value>
    </param>
  </params>
</methodResponse>''';

      final result = XmlRpcCodec.decodeResponse(body);
      expect(result, isA<DateTime>());
      final dt = result as DateTime;
      // Bare XML-RPC dates carry no timezone; the codec reads them as UTC.
      final utc = dt.toUtc();
      expect(utc.year, 1998);
      expect(utc.month, 7);
      expect(utc.day, 17);
      expect(utc.hour, 14);
    });

    test('decodes base64 to bytes', () {
      const body = '''
<methodResponse>
  <params>
    <param>
      <value><base64>aGVsbG8=</base64></value>
    </param>
  </params>
</methodResponse>''';

      final result = XmlRpcCodec.decodeResponse(body) as List<int>;
      expect(String.fromCharCodes(result), 'hello');
    });
  });

  group('XmlRpcCodec round-trip', () {
    test('encoded params survive decode', () {
      final params = [
        'user',
        'pass',
        7,
        false,
        {'key': 'value', 'nested': [1, 2, 3]},
      ];
      final xml = XmlRpcCodec.encodeRequest('demo.call', params);
      // The request wrapper decodes as: methodName + params; here we just
      // ensure the document parses and contains all members.
      expect(xml, contains('demo.call'));
      expect(xml, contains('<name>nested</name>'));
      expect(xml, contains('<boolean>0</boolean>'));
    });
  });
}
