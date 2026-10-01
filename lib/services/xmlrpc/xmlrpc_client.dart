import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  }) : _http = httpClient ?? http.Client() {
    // S1: warn (debug only) when credentials travel over plaintext HTTP.
    // XML-RPC uses HTTP Basic auth, so an http endpoint leaks the password.
    if (endpoint.scheme != 'https' && kDebugMode) {
      debugPrint(
        'WARNING: XML-RPC endpoint ${endpoint.host} is not HTTPS — '
        'credentials will be sent in cleartext.',
      );
    }
  }

  final Uri endpoint;
  final String username;
  final String password;
  final http.Client _http;

  static const _defaultTimeout = Duration(seconds: 30);

  /// Cap on response bytes. XML-RPC payloads are small text; an unbounded
  /// body lets an attacker abuse XXE/external-entity expansion (or simply a
  /// misbehaving server) into gigabytes of buffered memory (S3).
  static const _maxResponseBytes = 16 * 1024 * 1024; // 16 MiB

  /// Executes an XML-RPC method call and returns the decoded value.
  Future<dynamic> callMethod(
    String methodName,
    List<dynamic> params, {
    Duration timeout = _defaultTimeout,
  }) async {
    final body = XmlRpcCodec.encodeRequest(methodName, params);

    final request = http.Request('POST', endpoint)
      ..headers['Content-Type'] = 'text/xml; charset=utf-8'
      ..headers['User-Agent'] = 'OpenLiveWriter/1.5'
      ..body = body;
    http.StreamedResponse streamed;
    try {
      // R1: bound the send to the timeout. A stalled connection used to hang
      // forever on _http.send.
      streamed = await _http.send(request).timeout(timeout);
    } on XmlRpcFault {
      rethrow;
    } catch (e) {
      throw XmlRpcFault(-32300, 'Transport error calling $methodName: $e');
    }

    // S3 / P-07: read the response stream incrementally and enforce the byte
    // cap WHILE downloading. `http.Response.fromStream` buffers the entire
    // body first and only lets us inspect it afterward, so a hostile or
    // misbehaving server could still exhaust memory before the old check
    // ran. The capped read also guards the body-read against a slow/stalled
    // stream (the aggregate read is bounded by [timeout]).
    final bodyBytes = await _readCapped(streamed.stream, timeout);

    if (streamed.statusCode != 200) {
      final snippet = bodyBytes.length > 400
          ? '${utf8.decode(bodyBytes.sublist(0, 400))}…'
          : utf8.decode(bodyBytes);
      throw XmlRpcFault(
        -32300,
        'HTTP ${streamed.statusCode} from $methodName: $snippet',
      );
    }

    try {
      return XmlRpcCodec.decodeResponse(utf8.decode(bodyBytes));
    } on XmlRpcFault {
      rethrow;
    } catch (e) {
      throw XmlRpcFault(-32700, 'Failed to parse response of $methodName: $e');
    }
  }

  /// Reads [stream] into a byte buffer while enforcing [_maxResponseBytes].
  /// Throws [XmlRpcFault] if the cap is exceeded mid-download (the
  /// subscription is cancelled so no further bytes are buffered), and bounds
  /// the aggregate read to [timeout].
  Future<Uint8List> _readCapped(Stream<List<int>> stream, Duration timeout) {
    final completer = Completer<Uint8List>();
    final bytes = <int>[];
    Timer? timer;
    late StreamSubscription<List<int>> sub;
    timer = Timer(timeout, () {
      sub.cancel();
      completer.completeError(
        XmlRpcFault(-32300, 'Response read from $endpoint timed out'),
      );
    });
    sub = stream.listen(
      (chunk) {
        bytes.addAll(chunk);
        if (bytes.length > _maxResponseBytes) {
          sub.cancel();
          timer?.cancel();
          completer.completeError(
            XmlRpcFault(-32300, 'Response too large (${bytes.length} bytes)'),
          );
        }
      },
      onError: (e, st) {
        timer?.cancel();
        completer.completeError(e, st);
      },
      onDone: () {
        timer?.cancel();
        completer.complete(Uint8List.fromList(bytes));
      },
      cancelOnError: true,
    );
    return completer.future;
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
