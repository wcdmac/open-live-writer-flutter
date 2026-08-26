import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/blog.dart';
import 'xmlrpc_codec.dart';

/// Low-level XML-RPC transport: POSTs method calls to the endpoint,
/// decodes `<params>` responses and surfaces `<fault>` errors.
class XmlRpcClient {
  XmlRpcClient({
    required this.endpoint,
    required this.username,
    required this.password,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Uri endpoint;
  final String username;
  final String password;
  final http.Client _http;

  static const _defaultTimeout = Duration(seconds: 30);

  /// Raw body of the most recent response (truncated) — used by the
  /// in-app diagnostics when a post opens with empty content.
  String? lastResponseBody;

  /// Credentials used by most calls. `[Password, true]` in the original
  /// XmlRpcString marks an encode-required (HTML-escaped) string.
  List<dynamic> get cred => [username, password];

  /// Executes an XML-RPC method call and returns the decoded value.
  Future<dynamic> callMethod(
    String methodName,
    List<dynamic> params, {
    Duration timeout = _defaultTimeout,
  }) async {
    final body = XmlRpcCodec.encodeRequest(methodName, params);

    http.Response response;
    try {
      final request = http.Request('POST', endpoint)
        ..headers['Content-Type'] = 'text/xml; charset=utf-8'
        ..headers['User-Agent'] = 'OpenLiveWriter/1.5'
        ..body = body;
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on XmlRpcFault {
      rethrow;
    } catch (e) {
      throw XmlRpcFault(-32300, 'Transport error calling $methodName: $e');
    }

    lastResponseBody = response.body.length > 4000
        ? '${response.body.substring(0, 4000)}…'
        : response.body;

    if (response.statusCode != 200) {
      final snippet = response.body.length > 400
          ? '${response.body.substring(0, 400)}…'
          : response.body;
      throw XmlRpcFault(
        -32300,
        'HTTP ${response.statusCode} from $methodName: $snippet',
      );
    }

    try {
      return XmlRpcCodec.decodeResponse(utf8.decode(response.bodyBytes));
    } on XmlRpcFault {
      rethrow;
    } catch (e) {
      throw XmlRpcFault(-32700, 'Failed to parse response of $methodName: $e');
    }
  }

  void close() => _http.close();
}

/// Builds a [XmlRpcClient] for an account.
XmlRpcClient xmlRpcClientFor(BlogAccount account, String password) =>
    XmlRpcClient(
      endpoint: Uri.parse(account.apiUrl),
      username: account.username,
      password: password,
    );
