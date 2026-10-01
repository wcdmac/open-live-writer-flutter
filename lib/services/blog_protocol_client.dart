import '../models/blog.dart';
import '../models/blog_post.dart';
import 'rest/wordpress_rest.dart';
import 'xmlrpc/wordpress_xmlrpc.dart';

/// Normalized blog operations used by [BlogService], hiding whether the
/// underlying transport is REST or XML-RPC (P2-8).
///
/// Previously every method in [BlogService] branched on
/// `account.protocol == BlogProtocol.rest ? rest.x() : xmlrpc.x()` — ~15
/// duplicated ternary switches, so adding a protocol operation meant editing
/// the facade in two places and risking a divergent mapping (e.g. `modified`
/// was only ever filled by REST). A single [BlogProtocolClient] implementation
/// per protocol centralizes that mapping in one file.
abstract class BlogProtocolClient {
  Future<List<BlogInfo>> getUsersBlogs();

  Future<Map<String, dynamic>> getProfile();

  Future<List<BlogPost>> getPosts({
    int count = 30,
    int offset = 0,
    bool pages = false,
    PostStatus? status,
    List<String>? fields,
  });

  Future<BlogPost> getPost(String id, {bool isPage});

  Future<String> newPost(BlogPost post, {required bool publish});

  Future<bool> editPost(BlogPost post, {required bool publish});

  Future<bool> setPostStatus(String id, PostStatus status, {DateTime? date});

  Future<bool> deletePost(String id, {bool isPage});

  Future<List<PostCategory>> getCategories();

  Future<List<PostTag>> getTags();

  Future<String> newCategory(String name, {String? parentId});

  Future<MediaUploadResult> uploadMedia(
    String filename,
    List<int> bytes,
    String mimeType,
  );

  Future<Map<String, String>> getOptions();

  void dispose();
}

/// REST (WordPress REST API v2) implementation of [BlogProtocolClient].
///
/// Normalizes the REST client's return shapes to the facade contract:
/// `newPost` returns the created id (not the whole post), `editPost` returns
/// a bool, and `getOptions` maps the settings object to `String` values.
class RestProtocolClient implements BlogProtocolClient {
  RestProtocolClient(this._rest, {required this.account});

  final WordPressRestClient _rest;
  final BlogAccount account;

  @override
  Future<List<BlogInfo>> getUsersBlogs() async {
    final profile = await _rest.getProfile();
    final index = await _rest.getSiteIndex();
    return [
      BlogInfo(
        blogId: account.blogId,
        name: '${index['name'] ?? profile['name'] ?? 'Blog'}',
        url: account.homepageUrl,
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> getProfile() => _rest.getProfile();

  @override
  Future<List<BlogPost>> getPosts({
    int count = 30,
    int offset = 0,
    bool pages = false,
    PostStatus? status,
    List<String>? fields,
  }) =>
      _rest.getPosts(
        perPage: count,
        offset: offset,
        pages: pages,
        status: status,
        fields: fields,
      );

  @override
  Future<BlogPost> getPost(String id, {bool isPage = false}) =>
      _rest.getPost(id, isPage: isPage);

  @override
  Future<String> newPost(BlogPost post, {required bool publish}) async {
    final created = await _rest.newPost(post, publish: publish);
    return created.id ?? '';
  }

  @override
  Future<bool> editPost(BlogPost post, {required bool publish}) async {
    await _rest.editPost(post, publish: publish);
    return true;
  }

  @override
  Future<bool> setPostStatus(String id, PostStatus status, {DateTime? date}) =>
      _rest.editPostStatus(id, status, date: date);

  @override
  Future<bool> deletePost(String id, {bool isPage = false}) =>
      _rest.deletePost(id, isPage: isPage);

  @override
  Future<List<PostCategory>> getCategories() => _rest.getCategories();

  @override
  Future<List<PostTag>> getTags() => _rest.getTags();

  @override
  Future<String> newCategory(String name, {String? parentId}) async {
    final created = await _rest.newCategory(name, parentId: parentId);
    return created.id;
  }

  @override
  Future<MediaUploadResult> uploadMedia(
    String filename,
    List<int> bytes,
    String mimeType,
  ) =>
      _rest.uploadMedia(filename, bytes, mimeType);

  @override
  Future<Map<String, String>> getOptions() async {
    final settings = await _rest.getSettings();
    return settings.map((k, v) => MapEntry(k, '$v'));
  }

  @override
  void dispose() => _rest.close();
}

/// XML-RPC (WordPress / MetaWeblog / MovableType / Blogger) implementation of
/// [BlogProtocolClient]. The underlying client already exposes the same
/// method names, so this wrapper mostly forwards — but it pins the blog id
/// the server needs for post/taxonomy calls.
class XmlRpcProtocolClient implements BlogProtocolClient {
  XmlRpcProtocolClient(this._xmlrpc, {required this.flavor});

  final WordPressXmlRpcClient _xmlrpc;
  final XmlRpcFlavor flavor;

  @override
  Future<List<BlogInfo>> getUsersBlogs() => _xmlrpc.getUsersBlogs();

  @override
  Future<Map<String, dynamic>> getProfile() => _xmlrpc.getProfile();

  @override
  Future<List<BlogPost>> getPosts({
    int count = 30,
    int offset = 0,
    bool pages = false,
    PostStatus? status,
    List<String>? fields,
  }) =>
      _xmlrpc.getPosts(
        count: count,
        offset: offset,
        pages: pages,
        status: status,
      );

  @override
  Future<BlogPost> getPost(String id, {bool isPage = false}) =>
      _xmlrpc.getPost(id, isPage: isPage);

  @override
  Future<String> newPost(BlogPost post, {required bool publish}) =>
      _xmlrpc.newPost(post, publish: publish);

  @override
  Future<bool> editPost(BlogPost post, {required bool publish}) =>
      _xmlrpc.editPost(post, publish: publish);

  @override
  Future<bool> setPostStatus(String id, PostStatus status, {DateTime? date}) =>
      _xmlrpc.setPostStatus(id, status, date: date);

  @override
  Future<bool> deletePost(String id, {bool isPage = false}) =>
      _xmlrpc.deletePost(id);

  @override
  Future<List<PostCategory>> getCategories() => _xmlrpc.getCategories();

  @override
  Future<List<PostTag>> getTags() => _xmlrpc.getTags();

  @override
  Future<String> newCategory(String name, {String? parentId}) =>
      _xmlrpc.newCategory(name, parentId: parentId);

  @override
  Future<MediaUploadResult> uploadMedia(
    String filename,
    List<int> bytes,
    String mimeType,
  ) =>
      _xmlrpc.uploadMedia(filename, bytes, mimeType);

  @override
  Future<Map<String, String>> getOptions() => _xmlrpc.getOptions();

  @override
  void dispose() => _xmlrpc.close();
}
