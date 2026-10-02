import '../models/blog.dart';
import '../models/blog_post.dart';
import 'blog_protocol_client.dart';
import 'rest/wordpress_rest.dart';
import 'theme_detector.dart';
import 'xmlrpc/wordpress_xmlrpc.dart';
import 'xmlrpc/xmlrpc_client.dart';

/// Unified blog operations facade, hiding whether the account talks
/// XML-RPC (WordPress/MetaWeblog/MT/Blogger) or REST API v2.
///
/// This is the Flutter equivalent of OpenLiveWriter.BlogClient's
/// BlogClientProvider layer: same operations, modern transports.
///
/// P2-8: the protocol is chosen ONCE at construction (a [BlogProtocolClient]
/// per transport), so there are no per-method ternary branches and the
/// REST/XML-RPC field mapping lives in exactly one file
/// ([blog_protocol_client.dart]).
class BlogService {
  BlogService(this.account, this.password)
      : _client = account.protocol == BlogProtocol.rest
            ? RestProtocolClient(
                WordPressRestClient(
                  baseUrl: account.apiUrl,
                  username: account.username,
                  password: password,
                  authMethod: account.restAuth,
                ),
                account: account,
              )
            : XmlRpcProtocolClient(
                WordPressXmlRpcClient(
                  xmlRpcClientFor(account, password),
                  flavor: account.flavor,
                )..blogId = account.blogId,
                flavor: account.flavor,
              );

  final BlogAccount account;
  final String password;

  final BlogProtocolClient _client;

  // -------------------------------------------------------------------------
  // Blogs / profile
  // -------------------------------------------------------------------------

  Future<List<BlogInfo>> getUsersBlogs() => _client.getUsersBlogs();

  Future<Map<String, dynamic>> getProfile() => _client.getProfile();

  Future<List<BlogAuthor>> getAuthors() => _client.getAuthors();

  // -------------------------------------------------------------------------
  // Posts
  // -------------------------------------------------------------------------

  Future<List<BlogPost>> getPosts({
    int count = 30,
    int offset = 0,
    bool pages = false,
    PostStatus? status,
    List<String>? fields,
  }) =>
      _client.getPosts(
        count: count,
        offset: offset,
        pages: pages,
        status: status,
        fields: fields,
      );

  Future<BlogPost> getPost(String id, {bool isPage = false}) =>
      _client.getPost(id, isPage: isPage);

  /// Creates a new post. Returns the post id.
  Future<String> newPost(BlogPost post, {required bool publish}) =>
      _client.newPost(post, publish: publish);

  Future<bool> editPost(BlogPost post, {required bool publish}) =>
      _client.editPost(post, publish: publish);

  /// Changes ONLY the post status (dashboard quick actions) — avoids the
  /// full editPost payload, which is last-write-wins over title/content.
  /// [date] accompanies scheduled transitions (status=future needs a
  /// future date or WordPress publishes immediately).
  Future<bool> setPostStatus(
    String postId,
    PostStatus status, {
    DateTime? date,
  }) =>
      _client.setPostStatus(postId, status, date: date);

  Future<bool> deletePost(String id, {bool isPage = false}) =>
      _client.deletePost(id, isPage: isPage);

  // -------------------------------------------------------------------------
  // Taxonomies
  // -------------------------------------------------------------------------

  Future<List<PostCategory>> getCategories() => _client.getCategories();

  Future<List<PostTag>> getTags() => _client.getTags();

  Future<String> newCategory(String name, {String? parentId}) =>
      _client.newCategory(name, parentId: parentId);

  // -------------------------------------------------------------------------
  // Media
  // -------------------------------------------------------------------------

  Future<MediaUploadResult> uploadMedia(
    String filename,
    List<int> bytes,
    String mimeType,
  ) {
    return _client.uploadMedia(filename, bytes, mimeType);
  }

  // -------------------------------------------------------------------------
  // Site info
  // -------------------------------------------------------------------------

  Future<Map<String, String>> getOptions() => _client.getOptions();

  /// One theme probe per service instance: the detector allocates its own
  /// HTTP client, so it must be closed — a fresh ThemeDetector per call
  /// leaked a client (and re-fetched the homepage) on every refresh.
  Future<BlogTheme> detectTheme() async {
    final detector = ThemeDetector();
    try {
      return await detector.detect(account.homepageUrl);
    } finally {
      detector.close();
    }
  }

  /// Closes the underlying HTTP clients. Must run when the service is
  /// discarded (account switch/removal) or the connection pool leaks.
  void dispose() => _client.dispose();
}
