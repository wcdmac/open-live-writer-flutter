import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_live_writer/services/xmlrpc/wordpress_xmlrpc.dart';
import 'package:open_live_writer/services/xmlrpc/xmlrpc_client.dart';
import 'package:open_live_writer/services/xmlrpc/xmlrpc_codec.dart';

/// Regression tests: WordPress XML-RPC responses wrap HTML post content in
/// CDATA sections (titles stay plain text). If the decoder drops CDATA,
/// titles decode fine but bodies come back empty — exactly the
/// "title shows, content blank" symptom.
void main() {
  String responseFor(String contentXml) => '''
<?xml version="1.0"?>
<methodResponse>
  <params><param><value><struct>
    <member><name>post_id</name><value><int>5</int></value></member>
    <member><name>post_title</name><value><string><![CDATA[标题文字]]></string></value></member>
    <member><name>post_content</name><value><string>$contentXml</string></value></member>
  </struct></value></param></params>
</methodResponse>''';

  test('decodes CDATA-wrapped HTML content', () {
    final result = XmlRpcCodec.decodeResponse(
        responseFor('<![CDATA[<p>正文 <b>加粗</b> 内容</p>]]>'));
    expect(result, isA<Map>());
    expect(result['post_content'], '<p>正文 <b>加粗</b> 内容</p>');
  });

  test('decodes entity-escaped HTML content', () {
    final result = XmlRpcCodec.decodeResponse(
        responseFor('&lt;p&gt;正文&ampamp;内容&lt;/p&gt;'));
    expect(result['post_content'], contains('<p>'));
  });

  test('decodes mixed text + CDATA content', () {
    final result = XmlRpcCodec
        .decodeResponse(responseFor('前缀<![CDATA[<p>正文</p>]]>后缀'));
    expect(result['post_content'], contains('<p>正文</p>'));
  });

  // Captured from a live WordPress wp.getPost response: entity-escaped
  // content + FLAT terms array where each term carries its own taxonomy.
  test('wp.getPost parses live response: escaped content + flat terms',
      () async {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<methodResponse><params><param><value><struct>
<member><name>post_id</name><value><string>9</string></value></member>
<member><name>post_title</name><value><string>AI验证是否可用</string></value></member>
<member><name>post_content</name><value><string>&lt;!-- wp:paragraph --&gt;
&lt;p&gt;AI验证是否可用&lt;/p&gt;
&lt;!-- /wp:paragraph --&gt;</string></value></member>
<member><name>post_status</name><value><string>draft</string></value></member>
<member><name>link</name><value><string>https://example.com/?p=9</string></value></member>
<member><name>terms</name><value><array><data>
<value><struct>
<member><name>term_id</name><value><string>1</string></value></member>
<member><name>name</name><value><string>未分类</string></value></member>
<member><name>name</name><value><string>uncategorized</string></value></member>
<member><name>taxonomy</name><value><string>category</string></value></member>
</struct></value>
<value><struct>
<member><name>term_id</name><value><string>4</string></value></member>
<member><name>name</name><value><string>测试标签</string></value></member>
<member><name>taxonomy</name><value><string>post_tag</string></value></member>
</struct></value>
</data></array></value></member>
</struct></value></param></params></methodResponse>''';
    final mock = MockClient((req) async => http.Response.bytes(
        utf8.encode(xml), 200,
        headers: {'content-type': 'text/xml; charset=utf-8'}));
    final client = WordPressXmlRpcClient(XmlRpcClient(
      endpoint: Uri.parse('https://example.com/xmlrpc.php'),
      username: 'u',
      password: 'p',
      httpClient: mock,
    ));
    final post = await client.getPost('9');
    expect(post.title, 'AI验证是否可用');
    expect(post.content, startsWith('<!-- wp:paragraph -->'));
    expect(post.content, contains('<p>AI验证是否可用</p>'));
    expect(post.categories, ['1']);
    expect(post.tags, ['4']);
  });
}
