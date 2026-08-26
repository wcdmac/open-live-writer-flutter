import '../models/blog.dart';
import '../models/blog_post.dart';
import 'rest/wordpress_rest.dart';
import 'theme_detector.dart';
import 'xmlrpc/wordpress_xmlrpc.dart';
import 'xmlrpc/xmlrpc_client.dart';

/// Internal control-flow signal: the server returned a page we have
/// already seen (offset-ignoring metaWeblog fallback) — stop paging.
class _RepeatedPageSignal implements Exception {
  const _RepeatedPageSignal();
}

/// Unified blog operations facade, hiding whether the account talks
/// XML-RPC (WordPress/MetaWeblog/MT/Blogger) or REST API v2.
///
/// This is the Flutter equivalent of OpenLiveWriter.BlogClient's
/// BlogClientProvider layer: same operations, modern transports.
class BlogService {
  BlogService(this.account, this.password);

  final BlogAccount account;
  final String password;

  WordPressXmlRpcClient? _xmlrpc;
  WordPressRestClient? _rest;

  WordPressXmlRpcClient get xmlrpc {
    if (_xmlrpc == null) {
      final client = xmlRpcClientFor(account, password);
      final wp = WordPressXmlRpcClient(client, flavor: account.flavor);
      wp.blogId = account.blogId;
      _xmlrpc = wp;
    }
    return _xmlrpc!;
  }

  WordPressRestClient get rest => _rest ??= WordPressRestClient(
        baseUrl: account.apiUrl,
        username: account.username,
        password: password,
        authMethod: account.restAuth,
      );

  // -------------------------------------------------------------------------
  // Blogs / profile
  // -------------------------------------------------------------------------

  Future<List<BlogInfo>> getUsersBlogs() => account.protocol == BlogProtocol.rest
      ? _restUserBlogs()
      : xmlrpc.getUsersBlogs();

  Future<List<BlogInfo>> _restUserBlogs() async {
    final profile = await rest.getProfile();
    final index = await rest.getSiteIndex();
    return [
      BlogInfo(
        blogId: account.blogId,
        name: '${index['name'] ?? profile['name'] ?? 'Blog'}',
        url: account.homepageUrl,
      ),
    ];
  }

  Future<Map<String, dynamic>> getProfile() =>
      account.protocol == BlogProtocol.rest
          ? rest.getProfile()
          : xmlrpc.getProfile();

  // -------------------------------------------------------------------------
  // Posts
  // -------------------------------------------------------------------------

  Future<List<BlogPost>> getPosts(
          {int count = 30, bool pages = false, PostStatus? status}) =>
      account.protocol == BlogProtocol.rest
          ? rest.getPosts(perPage: count, pages: pages, status: status)
          : xmlrpc.getPosts(count: count, pages: pages, status: status);

  Future<BlogPost> getPost(String id, {bool isPage = false}) =>
      account.protocol == BlogProtocol.rest
          ? rest.getPost(id, isPage: isPage)
          : xmlrpc.getPost(id, isPage: isPage);

  /// Fetches every editable post (paged, protocol-specific). Used by the
  /// whole-blog WXR export.
  ///
  /// [onProgress] reports the running total after each page so the UI
  /// can show progress. [shouldCancel] is polled between pages; when it
  /// returns true the fetch stops and the posts fetched so far are
  /// returned. A batch that contains no new posts (servers whose
  /// metaWeblog fallback ignores the offset) also stops the loop —
  /// without this guard the fetch never terminates.
  Future<List<BlogPost>> getAllPosts({
    void Function(int fetched)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final all = <BlogPost>[];
    final seen = <String>{};
    const pageSize = 100;
    // Cross-border latency: a full page of 100 posts with content can
    // easily exceed the 30s default timeout.
    const timeout = Duration(minutes: 3);

    Future<void> append(List<BlogPost> batch) async {
      var added = 0;
      for (final post in batch) {
        final key = post.id ?? '${post.title}|${post.datePublished}';
        if (seen.add(key)) {
          all.add(post);
          added++;
        }
      }
      // Every post already seen: the server is repeating a page
      // (offset-ignoring metaWeblog fallback) — stop instead of
      // looping forever.
      if (batch.isNotEmpty && added == 0) {
        throw const _RepeatedPageSignal();
      }
    }

    try {
      if (account.protocol == BlogProtocol.rest) {
        var page = 1;
        while (true) {
          if (shouldCancel?.call() ?? false) return all;
          final batch = await rest
              .getPosts(perPage: pageSize, page: page, timeout: timeout);
          await append(batch);
          onProgress?.call(all.length);
          if (batch.length < pageSize) break;
          page++;
        }
      } else {
        var offset = 0;
        while (true) {
          if (shouldCancel?.call() ?? false) return all;
          final batch = await xmlrpc
              .getPosts(count: pageSize, offset: offset, timeout: timeout);
          await append(batch);
          onProgress?.call(all.length);
          if (batch.length < pageSize) break;
          offset += pageSize;
        }
      }
    } on _RepeatedPageSignal {
      // Repeated page: keep what we have, stop fetching.
    }
    return all;
  }

  /// Creates a new post. Returns the post id (XML-RPC) or the created
  /// post (REST gives us the full object back).
  Future<String> newPost(BlogPost post, {required bool publish}) async {
    if (account.protocol == BlogProtocol.rest) {
      final created = await rest.newPost(post, publish: publish);
      return created.id ?? '';
    }
    return xmlrpc.newPost(post, publish: publish);
  }

  Future<bool> editPost(BlogPost post, {required bool publish}) =>
      account.protocol == BlogProtocol.rest
          ? rest.editPost(post, publish: publish).then((_) => true)
          : xmlrpc.editPost(post, publish: publish);

  Future<bool> deletePost(String id, {bool isPage = false}) =>
      account.protocol == BlogProtocol.rest
          ? rest.deletePost(id, isPage: isPage)
          : xmlrpc.deletePost(id);

  // -------------------------------------------------------------------------
  // Taxonomies
  // -------------------------------------------------------------------------

  Future<List<PostCategory>> getCategories() =>
      account.protocol == BlogProtocol.rest
          ? rest.getCategories()
          : xmlrpc.getCategories();

  Future<List<PostTag>> getTags() => account.protocol == BlogProtocol.rest
      ? rest.getTags()
      : xmlrpc.getTags();

  Future<String> newCategory(String name, {String? parentId}) =>
      account.protocol == BlogProtocol.rest
          ? rest.newCategory(name, parentId: parentId).then((c) => c.id)
          : xmlrpc.newCategory(name, parentId: parentId);

  // -------------------------------------------------------------------------
  // Media
  // -------------------------------------------------------------------------

  Future<MediaUploadResult> uploadMedia(
          String filename, List<int> bytes, String mimeType) =>
      account.protocol == BlogProtocol.rest
          ? rest.uploadMedia(filename, bytes, mimeType)
          : xmlrpc.uploadMedia(filename, bytes, mimeType);

  // -------------------------------------------------------------------------
  // Site info
  // -------------------------------------------------------------------------

  Future<Map<String, String>> getOptions() async {
    if (account.protocol == BlogProtocol.rest) {
      final settings = await rest.getSettings();
      return settings.map((k, v) => MapEntry(k, '$v'));
    }
    return xmlrpc.getOptions();
  }

  Future<BlogTheme> detectTheme() => ThemeDetector().detect(account.homepageUrl);

  void dispose() {
    _xmlrpc = null;
    _rest = null;
  }
}
