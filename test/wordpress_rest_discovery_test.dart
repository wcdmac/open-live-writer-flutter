import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:open_live_writer/services/rest/wordpress_rest.dart';

void main() {
  group('WordPressRestClient.discoverRestRoot', () {
    test('returns root when the probe body advertises routes', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/wp-json/') {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"routes":{"/":{}}}')),
            200,
          );
        }
        // HEAD/GET on the homepage: no Link header, empty body.
        return http.StreamedResponse(Stream<List<int>>.empty(), 200);
      });
      final root = await WordPressRestClient.discoverRestRoot(
        'http://example.invalid/',
        client: client,
      );
      expect(root, 'http://example.invalid/wp-json');
    });

    test('does not throw on a probe body truncated mid multi-byte char (F5)',
        () async {
      // Mirrors the internal _maxResponseBytes cap. The probe read breaks once
      // the accumulated bytes exceed this, so a CJK code point straddling the
      // boundary would be a malformed trailing sequence.
      final cap = 16 * 1024 * 1024;
      final chunk1 = Uint8List(cap)..fillRange(0, cap, 0x20);
      // Byte just before the cap boundary is an incomplete CJK lead byte
      // (0xE4 leads 三). With its continuation missing, a raw utf8.decode would
      // throw FormatException; F5 adds allowMalformed so discovery survives it.
      chunk1[cap - 1] = 0xE4;
      final chunk2 = Uint8List(64)..fillRange(0, 64, 0x20);

      final client = MockClient((req) async {
        if (req.url.path == '/wp-json/') {
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([chunk1, chunk2]),
            200,
          );
        }
        return http.StreamedResponse(Stream<List<int>>.empty(), 200);
      });

      // The truncated probe body carries no 'namespaces'/'routes' marker, so
      // discovery returns null — but crucially without a FormatException.
      final root = await WordPressRestClient.discoverRestRoot(
        'http://example.invalid/',
        client: client,
      );
      expect(root, isNull);
    });
  });
}
