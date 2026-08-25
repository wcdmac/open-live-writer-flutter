import 'package:flutter_test/flutter_test.dart';
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
}
