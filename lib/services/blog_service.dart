import '../models/blog.dart';
import '../models/blog_post.dart';
import 'rest/wordpress_rest.dart';
import 'theme_detector.dart';
import 'xmlrpc/wordpress_xmlrpc.dart';
import 'xmlrpc/xmlrpc_client.dart';

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

  /// Diagnostics for the most recent getPost call, kept at the SERVICE
  /// level so it survives page navigation — the in-app "copy diagnostics"
  /// can then be triggered from any page and still reveal what happened
  /// when an article was opened.
  String? lastGetPostDiag;

  Future<BlogPost> getPost(String id, {bool isPage = false}) async {
    final sw = Stopwatch()..start();
    try {
      final post = account.protocol == BlogProtocol.rest
          ? await rest.getPost(id, isPage: isPage)
          : await xmlrpc.getPost(id, isPage: isPage);
      sw.stop();
      lastGetPostDiag = 'getPost($id): 成功 ${sw.elapsedMilliseconds}ms, '
          '标题=${post.title.length}字, 正文=${post.content.length}字, '
          '摘要=${post.excerpt.length}字, 分类=${post.categories.length}个, '
          '标签=${post.tags.length}个';
      return post;
    } catch (e) {
      sw.stop();
      lastGetPostDiag = 'getPost($id): 失败 ${sw.elapsedMilliseconds}ms ($e)';
      rethrow;
    }
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

  /// Raw body of the most recent HTTP response from the active client —
  /// surfaced by the in-app "copy diagnostics" action when a post opens
  /// with empty content, so the actual server payload can be inspected.
  String? get lastResponseBody => account.protocol == BlogProtocol.rest
      ? _rest?.lastResponseBody
      : _xmlrpc?.lastResponseBody;

  void dispose() {
    _xmlrpc = null;
    _rest = null;
  }
}
