import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_live_writer/models/blog.dart';
import 'package:open_live_writer/services/rest/wordpress_rest.dart';

/// Minimal fake [http.Client] that scripts canned responses for the JWT token
/// endpoint and the media upload endpoint, so we can exercise the upload
/// retry path without a real server.
class _FakeClient extends http.BaseClient {
  int mediaCalls = 0;
  final List<String> seenAuth = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final auth = request.headers['authorization'];
    if (auth != null) seenAuth.add(auth);
    if (path.contains('/jwt-auth/v1/token')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'token': 'tok123'}))),
        200,
        request: request,
      );
    }
    if (path.contains('/wp/v2/media')) {
      mediaCalls++;
      if (mediaCalls == 1) {
        // First attempt: JWT rejected → must trigger exactly one retry.
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"code":"jwt_auth_invalid_token"}')),
          401,
          request: request,
        );
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode(
          jsonEncode({'id': 7, 'source_url': 'https://x/a.jpg'}),
        )),
        200,
        request: request,
      );
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 404,
        request: request);
  }

  @override
  void close() {}
}

void main() {
  test('uploadMedia retries once after a 401 and clears the expired JWT (P1-2)',
      () async {
    final fake = _FakeClient();
    final client = WordPressRestClient(
      baseUrl: 'https://example.com/wp-json',
      username: 'u',
      password: 'p',
      authMethod: RestAuthMethod.jwt,
      httpClient: fake,
    );
    final result = await client.uploadMedia('a.jpg', [1, 2, 3], 'image/jpeg');
    // Two media attempts means the retry fired, and the second succeeded.
    expect(fake.mediaCalls, 2);
    expect(result.id, '7');
    expect(result.url, 'https://x/a.jpg');
    // The retry must have refetched the token (two Bearer auth headers seen).
    expect(fake.seenAuth.where((a) => a.startsWith('Bearer ')).length, 2);
    client.close();
  });
}
