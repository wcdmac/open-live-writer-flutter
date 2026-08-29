import '../../models/blog.dart';
import '../../models/blog_post.dart';
import 'xmlrpc_client.dart';
import 'xmlrpc_codec.dart';

/// Full XML-RPC blog client ported from Open Live Writer's client stack
/// (BloggerCompatibleClient -> MetaweblogClient -> MovableTypeClient ->
/// WordPressClient) with the same capability fallbacks:
///
///  * login:  wp.getUsersBlogs, fallback blogger.getUsersBlogs
///  * posts:  wp.getPosts/wp.newPost/wp.editPost, fallback metaWeblog.*
///  * cats:   wp.getCategories, fallback metaWeblog.getCategories,
///            fallback mt.getCategoryList
///  * media:  wp.uploadFile, fallback metaWeblog.newMediaObject
class WordPressXmlRpcClient {
  WordPressXmlRpcClient(this._client, {this.flavor = XmlRpcFlavor.wordpress});

  final XmlRpcClient _client;
  final XmlRpcFlavor flavor;

  String get _blogId => _clientEndpointBlogId;
  String _clientEndpointBlogId = '';

  /// Most calls need the blog id chosen at connect time.
  set blogId(String value) => _clientEndpointBlogId = value;

  // ---------------------------------------------------------------------------
  // Login / blog discovery
  // ---------------------------------------------------------------------------

  /// Port of BloggerCompatibleClient.Login + WordPressClient.GetUsersBlogs.
  Future<List<BlogInfo>> getUsersBlogs() async {
    // Preferred: wp.getUsersBlogs (WordPress flavor).
    if (flavor == XmlRpcFlavor.wordpress) {
      try {
        final result = await _client.callMethod('wp.getUsersBlogs',
            [_client.username, _client.password]);
        final blogs = _parseUserBlogs(result, 'wp.getUsersBlogs');
        if (blogs.isNotEmpty) return blogs;
      } on XmlRpcFault catch (e) {
        // Unknown method (405 / xml-rpc disabled) -> fall through.
        if (!_isMethodMissing(e)) rethrow;
      }
    }

    if (flavor == XmlRpcFlavor.blogger) {
      final result = await _client.callMethod('blogger.getUsersBlogs',
          ['', _client.username, _client.password]);
      return _parseUserBlogs(result, 'blogger.getUsersBlogs');
    }

    // MetaWeblog / MovableType servers commonly support blogger.getUsersBlogs.
    try {
      final result = await _client.callMethod('blogger.getUsersBlogs',
          ['', _client.username, _client.password]);
      final blogs = _parseUserBlogs(result, 'blogger.getUsersBlogs');
      if (blogs.isNotEmpty) return blogs;
    } on XmlRpcFault catch (e) {
      if (!_isMethodMissing(e)) rethrow;
    }

    final result = await _client.callMethod(
        'wp.getUsersBlogs', [_client.username, _client.password]);
    return _parseUserBlogs(result, 'wp.getUsersBlogs');
  }

  bool _isMethodMissing(XmlRpcFault e) =>
      e.code == 405 ||
      e.code == 404 ||
      e.message.toLowerCase().contains('method') ||
      e.message.toLowerCase().contains('xml-rpc');

  List<BlogInfo> _parseUserBlogs(dynamic result, String method) {
    final rows = result is List ? result : [result];
    final blogs = <BlogInfo>[];
    for (final row in rows) {
      if (row is Map) {
        blogs.add(BlogInfo.fromXmlRpcStruct(row));
      }
    }
    if (blogs.isEmpty && method == 'blogger.getUsersBlogs') {
      throw XmlRpcFault(-32700, 'Empty blog list from $method');
    }
    return blogs;
  }

  // ---------------------------------------------------------------------------
  // Posts (WordPress API with MetaWeblog fallback)
  // ---------------------------------------------------------------------------

  /// wp.getPosts / metaWeblog.getRecentPosts.
  Future<List<BlogPost>> getPosts({
    int count = 30,
    int offset = 0,
    bool pages = false,
    PostStatus? status,
  }) async {
    if (flavor == XmlRpcFlavor.wordpress || flavor == XmlRpcFlavor.movabletype) {
      try {
        Future<List<BlogPost>> wpGetPosts(dynamic postStatus) async {
          final filter = <String, dynamic>{
            'number': count,
            'offset': offset,
            if (pages) 'post_type': 'page',
            // WP_Query defaults to 'publish' only — pass every editable
            // status so drafts show up, but degrade on servers that
            // reject the multi-status filter.
            'post_status': postStatus,
          };
          final result = await _client.callMethod(
              'wp.getPosts', [_blogId, _client.username, _client.password, filter]);
          final rows = result is List ? result : [result];
          return rows
              .whereType<Map>()
              .map((m) => _postFromWpStruct(m, isPage: pages))
              .toList();
        }

        if (status != null) {
          return await wpGetPosts(status.wpValue);
        }
        try {
          return await wpGetPosts(
              ['publish', 'draft', 'future', 'pending', 'private', 'trash']);
        } on XmlRpcFault {
          // Degrade: some servers / roles reject the status array or the
          // private status wholesale (mirrors the REST permission model).
          // Keep a no-private tier so scheduled/trashed posts survive for
          // roles without read_private_posts.
          try {
            return await wpGetPosts(
                ['publish', 'draft', 'future', 'pending', 'trash']);
          } on XmlRpcFault {
            try {
              return await wpGetPosts(
                  'publish,draft,future,pending,private,trash');
            } on XmlRpcFault {
              try {
                return await wpGetPosts(
                    'publish,draft,future,pending,trash');
              } on XmlRpcFault {
                return await wpGetPosts(
                    'publish,draft,future,pending,private');
              }
            }
          }
        }
      } on XmlRpcFault catch (e) {
        if (!_isMethodMissing(e)) rethrow;
      }
    }

    final result = await _client.callMethod('metaWeblog.getRecentPosts',
        [_blogId, _client.username, _client.password, count]);
    final rows = result is List ? result : [result];
    return rows.whereType<Map>().map(_postFromMetaweblogStruct).toList();
  }

  /// wp.getPost / metaWeblog.getPost.
  Future<BlogPost> getPost(String postId, {bool isPage = false}) async {
    if (flavor == XmlRpcFlavor.wordpress) {
      try {
        final result = await _client.callMethod(
            'wp.getPost',
            [_blogId, _client.username, _client.password, int.tryParse(postId) ?? postId]);
        if (result is Map) return _postFromWpStruct(result, isPage: isPage);
      } on XmlRpcFault catch (e) {
        if (!_isMethodMissing(e)) rethrow;
      }
    }
    final result = await _client.callMethod(
        'metaWeblog.getPost', [postId, _client.username, _client.password]);
    if (result is! Map) {
      throw XmlRpcFault(-32700,
          'metaWeblog.getPost returned unexpected data for post $postId');
    }
    return _postFromMetaweblogStruct(result);
  }

  /// wp.newPost / metaWeblog.newPost. Returns the new post id.
  ///
  /// Saves use a 3-minute timeout: full-post bodies over slow cross-border
  /// links can exceed the 30s default — the edit still lands server-side
  /// while the client reports a bogus "transport error".
  Future<String> newPost(BlogPost post, {required bool publish}) async {
    const saveTimeout = Duration(minutes: 3);
    // WordPress rejects status=trash on creation (same as REST); degrade
    // to draft instead of failing the whole save.
    if (post.status == PostStatus.trash) post.status = PostStatus.draft;
    if (flavor == XmlRpcFlavor.wordpress || flavor == XmlRpcFlavor.movabletype) {
      try {
        final content = _wpPostStruct(post, publish: publish);
        final result = await _client.callMethod('wp.newPost',
            [_blogId, _client.username, _client.password, content],
            timeout: saveTimeout);
        return _asId(result);
      } on XmlRpcFault catch (e) {
        if (!_isMethodMissing(e)) rethrow;
      }
    }
    final content = _metaweblogPostStruct(post);
    final result = await _client.callMethod('metaWeblog.newPost',
        [_blogId, _client.username, _client.password, content, publish],
        timeout: saveTimeout);
    final id = _asId(result);
    // MetaWeblog needs out-of-band category + tag calls.
    if (post.categories.isNotEmpty) {
      await setPostCategories(id, post.categories);
    }
    if (post.tags.isNotEmpty) {
      // mt_keywords is handled inside the struct for MT-compatible servers;
      // WordPress XML-RPC reads tags from mt_keywords too.
    }
    return id;
  }

  /// wp.editPost / metaWeblog.editPost.
  Future<bool> editPost(BlogPost post, {required bool publish}) async {
    const saveTimeout = Duration(minutes: 3);
    if (flavor == XmlRpcFlavor.wordpress || flavor == XmlRpcFlavor.movabletype) {
      try {
        final content = _wpPostStruct(post, publish: publish);
        final result = await _client.callMethod('wp.editPost',
            [_blogId, _client.username, _client.password, post.id, content],
            timeout: saveTimeout);
        return result == true || result == 1 || '$result' == 'true';
      } on XmlRpcFault catch (e) {
        if (!_isMethodMissing(e)) rethrow;
      }
    }
    final content = _metaweblogPostStruct(post);
    final result = await _client.callMethod('metaWeblog.editPost',
        [post.id, _client.username, _client.password, content, publish],
        timeout: saveTimeout);
    if (post.categories.isNotEmpty) {
      await setPostCategories(post.id!, post.categories);
    }
    return result == true || result == 1 || '$result' == 'true';
  }

  /// Changes ONLY the post status via wp.editPost — used by dashboard quick
  /// actions so a status change never re-sends (and overwrites) the whole
  /// post content. [date] accompanies scheduled transitions (WordPress
  /// needs a future date to keep status=future).
  Future<bool> setPostStatus(String postId, PostStatus status,
      {DateTime? date}) async {
    final result = await _client.callMethod('wp.editPost', [
      _blogId,
      _client.username,
      _client.password,
      int.tryParse(postId) ?? postId,
      {
        'post_status': status.wpValue,
        if (date != null)
          'post_date_gmt': date.toUtc().toIso8601String(),
      },
    ]);
    return result == true || result == 1 || '$result' == 'true';
  }

  /// blogger.deletePost / wp.deletePost.
  Future<bool> deletePost(String postId) async {
    if (flavor == XmlRpcFlavor.wordpress) {
      try {
        final result = await _client.callMethod(
            'wp.deletePost',
            [_blogId, _client.username, _client.password,
             int.tryParse(postId) ?? postId]);
        return result == true || result == 1;
      } on XmlRpcFault catch (e) {
        if (!_isMethodMissing(e)) rethrow;
      }
    }
    final result = await _client.callMethod('blogger.deletePost',
        ['', postId, _client.username, _client.password, true]);
    return result == true || result == 1;
  }

  /// mt.publishPost - force publish a draft.
  Future<bool> publishPost(String postId) async {
    final result = await _client.callMethod(
        'mt.publishPost', [postId, _client.username, _client.password]);
    return result != null;
  }

  // ---------------------------------------------------------------------------
  // Categories & tags
  // ---------------------------------------------------------------------------

  /// Port of MetaweblogClient.GetCategories with flavor fallbacks.
  Future<List<PostCategory>> getCategories() async {
    // WordPress flavor: wp.getCategories (hierarchical).
    if (flavor == XmlRpcFlavor.wordpress) {
      try {
        final result = await _client.callMethod(
            'wp.getCategories', [_blogId, _client.username, _client.password]);
        final rows = result is List ? result : [result];
        return rows.whereType<Map>().map((m) {
          return PostCategory(
            id: '${m['categoryId'] ?? m['category_id'] ?? ''}',
            name: '${m['categoryName'] ?? m['category_name'] ?? ''}',
            parentId: m['parentId'] == null ? null : '${m['parentId']}',
            description: m['description'] == null ? null : '${m['description']}',
            slug: m['slug'] == null ? null : '${m['slug']}',
          );
        }).toList();
      } on XmlRpcFault catch (e) {
        if (!_isMethodMissing(e)) rethrow;
      }
    }

    // MetaWeblog: metaWeblog.getCategories.
    try {
      final result = await _client.callMethod('metaWeblog.getCategories',
          [_blogId, _client.username, _client.password]);
      final rows = result is List ? result : [result];
      return rows.whereType<Map>().map((m) {
        return PostCategory(
          id: '${m['categoryId'] ?? m['categoryid'] ?? m['description'] ?? ''}',
          name: '${m['categoryName'] ?? m['name'] ?? m['title'] ?? ''}',
          description: m['description'] == null ? null : '${m['description']}',
          slug: m['slug'] == null ? null : '${m['slug']}',
        );
      }).toList();
    } on XmlRpcFault catch (e) {
      if (!_isMethodMissing(e)) rethrow;
    }

    // MovableType: mt.getCategoryList.
    final result = await _client.callMethod(
        'mt.getCategoryList', [_blogId, _client.username, _client.password]);
    final rows = result is List ? result : [result];
    return rows.whereType<Map>().map((m) {
      return PostCategory(
        id: '${m['categoryId'] ?? ''}',
        name: '${m['categoryName'] ?? m['name'] ?? ''}',
        parentId: m['parentId'] == null ? null : '${m['parentId']}',
      );
    }).toList();
  }

  /// wp.newCategory. Returns the new category id.
  Future<String> newCategory(String name, {String? parentId, String? slug}) async {
    final struct = <String, dynamic>{
      'name': name,
      'slug': ?slug,
      if (parentId != null && parentId.isNotEmpty)
        'parent_id': int.tryParse(parentId) ?? parentId,
    };
    final result = await _client.callMethod(
        'wp.newCategory', [_blogId, _client.username, _client.password, struct]);
    return _asId(result);
  }

  /// mt.getPostCategories for a post.
  Future<List<String>> getPostCategories(String postId) async {
    try {
      final result = await _client.callMethod(
          'mt.getPostCategories', [postId, _client.username, _client.password]);
      final rows = result is List ? result : [result];
      return rows
          .whereType<Map>()
          .map((m) => '${m['categoryId'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toList();
    } on XmlRpcFault {
      return const [];
    }
  }

  /// mt.setPostCategories.
  Future<void> setPostCategories(String postId, List<String> categoryIds) async {
    final categories = categoryIds
        .map((id) => {'categoryId': int.tryParse(id) ?? id})
        .toList();
    await _client.callMethod(
        'mt.setPostCategories', [postId, _client.username, _client.password, categories]);
  }

  /// Port of WordPressGetKeywords (wp.getTags).
  Future<List<PostTag>> getTags() async {
    try {
      final result = await _client.callMethod(
          'wp.getTags', [_blogId, _client.username, _client.password]);
      final rows = result is List ? result : [result];
      return rows.whereType<Map>().map((m) {
        return PostTag(
          id: '${m['term_id'] ?? m['tag_id'] ?? ''}',
          name: '${m['name'] ?? m['title'] ?? ''}',
          slug: m['slug'] == null ? null : '${m['slug']}',
        );
      }).toList();
    } on XmlRpcFault catch (e) {
      if (_isMethodMissing(e)) return const [];
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Media
  // ---------------------------------------------------------------------------

  /// wp.uploadFile / metaWeblog.newMediaObject.
  ///
  /// Uses a dedicated 5-minute timeout: media uploads travel cross-border,
  /// base64-encoded (~33% larger), and the server re-encodes images — the
  /// default 30s call timeout aborts them mid-flight (transport error -32300).
  Future<MediaUploadResult> uploadMedia(
      String filename, List<int> bytes, String mimeType) async {
    const uploadTimeout = Duration(minutes: 5);
    final data = <String, dynamic>{
      'name': filename,
      'type': mimeType,
      'bits': bytes, // encoded as base64 by the codec
      if (flavor == XmlRpcFlavor.wordpress) 'overwrite': false,
    };
    try {
      final result = await _client.callMethod(
          'wp.uploadFile', [_blogId, _client.username, _client.password, data],
          timeout: uploadTimeout);
      if (result is Map) return _mediaFromStruct(result);
    } on XmlRpcFault catch (e) {
      if (!_isMethodMissing(e)) rethrow;
    }
    final result = await _client.callMethod(
        'metaWeblog.newMediaObject',
        [_blogId, _client.username, _client.password, data],
        timeout: uploadTimeout);
    return _mediaFromStruct(result as Map);
  }

  MediaUploadResult _mediaFromStruct(Map m) => MediaUploadResult(
        id: '${m['id'] ?? m['attachment_id'] ?? ''}',
        url: '${m['url'] ?? ''}',
        file: m['file'] == null ? null : '${m['file']}',
        type: m['type'] == null ? null : '${m['type']}',
        thumbnailUrl:
            m['thumbnail'] == null ? null : '${m['thumbnail']}',
      );

  // ---------------------------------------------------------------------------
  // Options, profile, comments (WordPress extras)
  // ---------------------------------------------------------------------------

  /// wp.getOptions - returns raw name/value map.
  Future<Map<String, String>> getOptions() async {
    try {
      final result = await _client.callMethod(
          'wp.getOptions', [_blogId, _client.username, _client.password]);
      final map = <String, String>{};
      if (result is Map) {
        result.forEach((key, value) {
          if (value is Map) {
            map['$key'] = '${value['value'] ?? ''}';
          } else {
            map['$key'] = '$value';
          }
        });
      }
      return map;
    } on XmlRpcFault {
      return const {};
    }
  }

  /// wp.getProfile.
  Future<Map<String, dynamic>> getProfile() async {
    final result = await _client.callMethod(
        'wp.getProfile', [_blogId, _client.username, _client.password]);
    return result is Map ? Map<String, dynamic>.from(result) : const {};
  }

  /// wp.getComments (paginated).
  Future<List<Map<String, dynamic>>> getComments({int count = 30}) async {
    try {
      final result = await _client.callMethod('wp.getComments', [
        _blogId,
        _client.username,
        _client.password,
        {'number': count, 'status': 'hold'}
      ]);
      final rows = result is List ? result : [result];
      return rows.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    } on XmlRpcFault {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Struct builders
  // ---------------------------------------------------------------------------

  /// WordPress content struct (wp.newPost / wp.editPost).
  Map<String, dynamic> _wpPostStruct(BlogPost post, {required bool publish}) {
    // publish=false means "Save draft"; publish=true sends the status
    // exactly as the editor chose it (EditorState handles the untouched
    // draft → publish default) — converting here would silently revert
    // explicit choices like published → draft.
    final status = publish ? post.status : PostStatus.draft;
    return {
      'post_type': post.isPage ? 'page' : 'post',
      'post_status': status.wpValue,
      'post_title': post.title,
      'post_content': post.content,
      'post_excerpt': post.excerpt,
      if (post.slug?.isNotEmpty == true) 'post_name': post.slug,
      if (post.datePublished != null) 'post_date_gmt': post.datePublished,
      if (post.password?.isNotEmpty == true) 'post_password': post.password,
      if (post.isPage) ...{
        if (post.pageParentId?.isNotEmpty == true)
          'wp_page_parent_id': int.tryParse(post.pageParentId!) ?? post.pageParentId,
        if (post.pageOrder != null) 'wp_page_order': post.pageOrder,
      } else ...{
        // Tags: numeric values are term ids; names must ride terms_names
        // (wp.newPost creates them server-side) — the plain terms field
        // accepts ids only, so names there are silently dropped.
        ...() {
          final tagIds =
              post.tags.where((t) => int.tryParse(t) != null).toList();
          final tagNames =
              post.tags.where((t) => int.tryParse(t) == null).toList();
          return {
            'terms': {
              'category': post.categories
                  .map((c) => int.tryParse(c) ?? c)
                  .toList(),
              if (tagIds.isNotEmpty) 'post_tag': tagIds,
            },
            if (tagNames.isNotEmpty)
              'terms_names': {'post_tag': tagNames},
          };
        }(),
        'comment_status': post.commentsEnabled ? 'open' : 'closed',
        'ping_status': post.pingsEnabled ? 'open' : 'closed',
      },
    };
  }

  /// MetaWeblog content struct (metaWeblog.newPost / editPost).
  Map<String, dynamic> _metaweblogPostStruct(BlogPost post) {
    return {
      'title': post.title,
      'description': post.content,
      'mt_excerpt': post.excerpt,
      'dateCreated': post.datePublished,
      if (post.slug?.isNotEmpty == true) 'wp_slug': post.slug,
      'categories': post.categories,
      'mt_keywords': post.tags.join(','),
      'mt_allow_comments': post.commentsEnabled ? 1 : 0,
      'mt_allow_pings': post.pingsEnabled ? 1 : 0,
      if (post.isPage) ...{
        if (post.pageParentId?.isNotEmpty == true)
          'wp_page_parent_id': post.pageParentId,
        if (post.pageOrder != null) 'wp_page_order': post.pageOrder,
      },
    };
  }

  /// Parses a wp.getPosts struct.
  BlogPost _postFromWpStruct(Map m, {bool isPage = false}) {
    List<String> extractTerms(dynamic terms, String taxonomy) {
      // wp.getPost / wp.getPosts return a FLAT array of term structs,
      // each carrying its own `taxonomy` field (confirmed against live
      // WordPress responses) — not a {taxonomy: [...]} map.
      if (terms is List) {
        return terms
            .whereType<Map>()
            .where((t) => '${t['taxonomy'] ?? ''}' == taxonomy)
            .map((t) => '${t['term_id'] ?? t['name'] ?? ''}')
            .where((s) => s.isNotEmpty)
            .toList();
      }
      // Some servers wrap terms as {taxonomy: [structs]} — keep support.
      if (terms is Map) {
        final list = terms[taxonomy];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((t) => '${t['term_id'] ?? t['name'] ?? ''}')
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
      return const [];
    }

    DateTime? parseDate(dynamic raw) {
      if (raw is DateTime) return raw;
      if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
      return null;
    }

    final status = PostStatus.fromWp('${m['post_status'] ?? 'draft'}');
    return BlogPost(
      id: '${m['post_id'] ?? ''}',
      title: '${m['post_title'] ?? ''}',
      content: '${m['post_content'] ?? ''}',
      excerpt: '${m['post_excerpt'] ?? ''}',
      slug: m['post_name'] == null || '${m['post_name']}'.isEmpty
          ? null
          : '${m['post_name']}',
      permalink: m['link'] == null ? null : '${m['link']}',
      status: status,
      isPage: isPage,
      authorId: m['post_author'] == null ? null : '${m['post_author']}',
      dateCreated: parseDate(m['post_date_gmt'] ?? m['post_date']),
      datePublished: parseDate(m['post_date_gmt'] ?? m['post_date']),
      commentsEnabled: '${m['comment_status'] ?? 'open'}' == 'open',
      pingsEnabled: '${m['ping_status'] ?? 'open'}' == 'open',
      categories: extractTerms(m['terms'], 'category'),
      tags: extractTerms(m['terms'], 'post_tag'),
    );
  }

  /// Parses a metaWeblog.getPost struct.
  BlogPost _postFromMetaweblogStruct(Map m) {
    DateTime? parseDate(dynamic raw) => raw is DateTime ? raw : null;

    List<String> cats = const [];
    if (m['categories'] is List) {
      cats = (m['categories'] as List)
          .map((c) => '$c')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    List<String> tags = const [];
    final kw = '${m['mt_keywords'] ?? ''}';
    if (kw.isNotEmpty) {
      tags = kw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    return BlogPost(
      id: '${m['postid'] ?? m['postId'] ?? ''}',
      title: '${m['title'] ?? ''}',
      content: '${m['description'] ?? ''}',
      excerpt: '${m['mt_excerpt'] ?? ''}',
      slug: m['wp_slug'] == null || '${m['wp_slug']}'.isEmpty
          ? null
          : '${m['wp_slug']}',
      permalink: m['permalink'] == null ? null : '${m['permalink']}',
      status: PostStatus.fromWp('${m['post_status'] ?? 'draft'}'),
      authorName: m['userid'] == null ? null : '${m['userid']}',
      dateCreated: parseDate(m['dateCreated']),
      datePublished: parseDate(m['dateCreated']),
      commentsEnabled: '${m['mt_allow_comments'] ?? 1}' != '0',
      pingsEnabled: '${m['mt_allow_pings'] ?? 1}' != '0',
      categories: cats,
      tags: tags,
    );
  }

  String _asId(dynamic value) {
    if (value is Map) return '${value['postid'] ?? value['postId'] ?? ''}';
    return '$value';
  }

  /// Releases the underlying HTTP client (called by BlogService.dispose).
  void close() => _client.close();
}
