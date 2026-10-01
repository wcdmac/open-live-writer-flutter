import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/models/blog.dart';
import 'package:open_live_writer/services/blog_service.dart';

BlogAccount _account({BlogProtocol protocol = BlogProtocol.rest}) => BlogAccount(
      id: 'a1',
      blogId: '1',
      name: 'Blog',
      homepageUrl: 'https://example.com',
      apiUrl: 'https://example.com/wp-json',
      protocol: protocol,
      username: 'u',
    );

void main() {
  group('BlogService', () {
    // ----------------------------------------------------------------- P-04
    test('disposed service throws instead of rebuilding a leaked client (P-04)',
        () {
      final svc = BlogService(_account(), 'p');
      // Before dispose, clients are constructed lazily (no network call).
      expect(svc.rest, isNotNull);
      expect(svc.xmlrpc, isNotNull);

      svc.dispose();
      // After dispose, any access must fail loudly rather than silently
      // allocate a new http.Client that would never be closed.
      expect(() => svc.rest, throwsA(isA<StateError>()));
      expect(() => svc.xmlrpc, throwsA(isA<StateError>()));
    });

    test('dispose is idempotent', () {
      final svc = BlogService(_account(protocol: BlogProtocol.xmlrpc), 'p');
      svc.dispose();
      svc.dispose(); // must not throw
      expect(() => svc.xmlrpc, throwsA(isA<StateError>()));
    });
  });
}
