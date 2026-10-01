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
    // P2-8: the protocol client is chosen once at construction. Both paths
    // must build (no network at construction) and dispose cleanly + idempotently
    // so the underlying HTTP pool is never leaked across account switches.
    test('REST service constructs and disposes idempotently', () {
      final svc = BlogService(_account(), 'p');
      svc.dispose();
      svc.dispose(); // must not throw
    });

    test('XML-RPC service constructs and disposes idempotently', () {
      final svc = BlogService(_account(protocol: BlogProtocol.xmlrpc), 'p');
      svc.dispose();
      svc.dispose(); // must not throw
    });

    test('facade exposes the same operation surface for both protocols', () {
      // Compile-time + shape check: the unified facade exposes every operation
      // regardless of transport, so callers never branch on protocol.
      final rest = BlogService(_account(), 'p');
      final xml = BlogService(_account(protocol: BlogProtocol.xmlrpc), 'p');
      for (final svc in [rest, xml]) {
        expect(svc.getUsersBlogs, isNotNull);
        expect(svc.getProfile, isNotNull);
        expect(svc.getPosts, isNotNull);
        expect(svc.getPost, isNotNull);
        expect(svc.newPost, isNotNull);
        expect(svc.editPost, isNotNull);
        expect(svc.setPostStatus, isNotNull);
        expect(svc.deletePost, isNotNull);
        expect(svc.getCategories, isNotNull);
        expect(svc.getTags, isNotNull);
        expect(svc.newCategory, isNotNull);
        expect(svc.uploadMedia, isNotNull);
        expect(svc.getOptions, isNotNull);
        expect(svc.detectTheme, isNotNull);
      }
      rest.dispose();
      xml.dispose();
    });
  });
}
