import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/blog.dart';
import '../../models/blog_post.dart';

/// Exception carrying HTTP status + REST API error payload.
class WordPressRestException implements Exception {
  WordPressRestException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() =>
      'WordPress REST error $statusCode ($code): $message';
}

/// WordPress REST API v2 client — the modern companion to XML-RPC.
///
/// Supported authentication strategies:
///  * [RestAuthMethod.applicationPassword] — HTTP Basic with an
///    Application Password (WordPress 5.6+, recommended).
///  * [RestAuthMethod.jwt] — JWT Bearer tokens via the
///    `jwt-auth` plugin (`/wp-json/jwt-auth/v1/token`).
///
/// Endpoints are auto-discovered from the site's `Link` header
/// (`rel="https://api.w.org/"`) or `?rest_route=` fallback.
class WordPressRestClient {
  WordPressRestClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.authMethod = RestAuthMethod.applicationPassword,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// REST root, e.g. `https://example.com/wp-json`.
  final String baseUrl;
  final String username;
  final String password;
  final RestAuthMethod authMethod;
  final http.Client _http;

  String? _jwtToken;

  /// In-flight JWT fetch, shared by concurrent requests so a burst of
  /// calls doesn't fire N token authentications at once.
  Future<String?>? _jwtFuture;

  /// Cached tag list for name→id resolution on save (see [_resolveTagIds]).
  List<PostTag>? _tagCache;

  /// Last status query the server accepted for getPosts — skips the
  /// 3-request degrade chain on every refresh (see [getPosts]).
  String? _workingStatusQuery;

  static const _timeout = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Detects the REST root for a WordPress site.
  /// Mirrors RSD discovery: HEAD/GET the homepage, read the
  /// `Link: <https://site/wp-json/>; rel="https://api.w.org/"` header.
  static Future<String?> discoverRestRoot(String homepageUrl,
      {http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse(homepageUrl);
      http.Response? res;
      try {
        res = await httpClient.head(uri).timeout(_timeout);
      } catch (_) {/* fall through to GET */}
      res ??= await httpClient.get(uri).timeout(_timeout);
      final link = res.headers['link'];
      if (link != null) {
        final m = RegExp(r'<([^>]+)>;\s*rel="https://api\.w\.org/"')
            .firstMatch(link);
        if (m != null) return m.group(1)!.replaceAll(RegExp(r'/+$'), '');
      }
      // Fallback: probe the default location.
      final probe = await httpClient
          .get(Uri.parse(
              '${homepageUrl.replaceAll(RegExp(r'/+$'), '')}/wp-json/'))
          .timeout(_timeout);
      if (probe.statusCode == 200 &&
          (probe.body.contains('namespaces') ||
              probe.body.contains('routes'))) {
        return '${homepageUrl.replaceAll(RegExp(r'/+$'), '')}/wp-json';
      }
      return null;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _headers(
      {Map<String, String> extra = const {}}) async {
    final h = <String, String>{
      'User-Agent': 'OpenLiveWriter/1.5',
      'Accept': 'application/json',
      ...extra,
    };
    switch (authMethod) {
      case RestAuthMethod.applicationPassword:
        final token = base64Encode(utf8.encode('$username:$password'));
        h['Authorization'] = 'Basic $token';
      case RestAuthMethod.jwt:
        _jwtToken ??= await (_jwtFuture ??= _fetchJwtToken()
            .whenComplete(() => _jwtFuture = null));
        if (_jwtToken != null) h['Authorization'] = 'Bearer $_jwtToken';
    }
    return h;
  }

  Future<String?> _fetchJwtToken() async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/jwt-auth/v1/token'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(_timeout);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      return body is Map ? body['token'] as String? : null;
    }
    throw WordPressRestException(
        res.statusCode, 'jwt_auth_failed', 'JWT authentication failed');
  }

  // ---------------------------------------------------------------------------
  // Core request helpers
  // ---------------------------------------------------------------------------

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String> extraHeaders = const {},
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final headers = await _headers(
      extra: {
        if (body != null) 'Content-Type': 'application/json',
        ...extraHeaders,
      },
    );
    // Never attach a body to GET/DELETE requests — some WAFs (Cloudflare,
    // BT panel…) reject non-empty or zero-length bodies on GET with 403.
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null && method.toUpperCase() != 'GET') {
      request.body = jsonEncode(body);
    }
    final res = await _http.send(request).timeout(timeout ?? _timeout);
    final response = await http.Response.fromStream(res);

    if (response.statusCode >= 400) {
      String code = 'http_error';
      String message = response.reasonPhrase ?? 'Request failed';
      try {
        final err = jsonDecode(utf8.decode(response.bodyBytes));
        if (err is Map) {
          code = '${err['code'] ?? code}';
          message = '${err['message'] ?? message}';
        }
      } catch (_) {/* keep defaults */}
      // JWT tokens can expire; invalidate so the next call re-authenticates.
      if (response.statusCode == 401 && authMethod == RestAuthMethod.jwt) {
        _jwtToken = null;
      }
      throw WordPressRestException(response.statusCode, code, message);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  // ---------------------------------------------------------------------------
  // Users
  // ---------------------------------------------------------------------------

  /// GET /wp/v2/users/me — validates credentials and returns the profile.
  Future<Map<String, dynamic>> getProfile() async {
    final data = await _request('GET', '/wp/v2/users/me',
        query: {'context': 'edit'});
    if (data is Map<String, dynamic>) return data;
    throw WordPressRestException(500, 'invalid_profile', 'Bad profile payload');
  }

  // ---------------------------------------------------------------------------
  // Posts & pages
  // ---------------------------------------------------------------------------

  Future<List<BlogPost>> getPosts({
    int perPage = 30,
    int page = 1,
    bool pages = false,
    PostStatus? status,
    String search = '',
  }) async {
    Future<List<BlogPost>> fetch(String statuses) async {
      final data = await _request('GET', '/wp/v2/${pages ? 'pages' : 'posts'}',
          query: {
            'context': 'edit',
            'per_page': '$perPage',
            'page': '$page',
            'status': statuses,
            if (search.isNotEmpty) 'search': search,
          });
      if (data is! List) return const [];
      return data
          .map((raw) => _postFromJson(raw as Map, isPage: pages))
          .toList();
    }

    // Without an explicit status the REST API only returns 'publish'.
    // Request every editable status first so drafts show up, but degrade
    // gracefully: roles without permission for private/future statuses get
    // the WHOLE request rejected (rest_invalid_status / rest_forbidden),
    // which used to leave the dashboard permanently empty.
    final explicit = status?.wpValue;
    if (explicit != null) return fetch(explicit);

    // Remember the last query the server accepted; retry it first on the
    // next call instead of walking the whole degrade chain again.
    final cached = _workingStatusQuery;
    if (cached != null) {
      try {
        return await fetch(cached);
      } on WordPressRestException catch (e) {
        if (e.statusCode != 400 && e.statusCode != 401 && e.statusCode != 403) {
          rethrow;
        }
        _workingStatusQuery = null;
      }
    }
    for (final query in const [
      'publish,draft,future,pending,private,trash',
      'publish,draft,future,pending,private',
      'publish,draft,pending',
      'publish',
    ]) {
      try {
        final result = await fetch(query);
        _workingStatusQuery = query;
        return result;
      } on WordPressRestException catch (e) {
        if (e.statusCode != 400 && e.statusCode != 401 && e.statusCode != 403) {
          rethrow;
        }
      }
    }
    // Unreachable: the last query ('publish') is always accepted.
    return fetch('publish');
  }

  Future<BlogPost> getPost(String id, {bool isPage = false}) async {
    Future<BlogPost> fetch(String context) async {
      final data = await _request(
          'GET', '/wp/v2/${isPage ? 'pages' : 'posts'}/$id',
          query: {'context': context});
      return _postFromJson(data as Map, isPage: isPage);
    }

    try {
      return await fetch('edit');
    } on WordPressRestException catch (e) {
      // Roles that may list posts but lack edit permission on this one
      // (e.g. a contributor opening someone else's post) get 401/403 for
      // context=edit — fall back to the rendered (view) content instead
      // of failing with an empty editor.
      if (e.statusCode == 401 || e.statusCode == 403) {
        return fetch('view');
      }
      rethrow;
    }
  }

  /// Saves (new/edit/status/delete) tolerate cross-border latency: the
  /// request often REACHES the server and succeeds while the response
  /// crawls back — a short timeout here used to misclassify a successful
  /// publish as a network failure (ghost-draft bug).
  static const _saveTimeout = Duration(minutes: 3);

  Future<BlogPost> newPost(BlogPost post, {required bool publish}) async {
    // Defense in depth: WordPress rejects status=trash on creation with
    // rest_invalid_param — the editor hides the option, but any other
    // path (draft restore, etc.) degrades to draft instead of failing.
    if (post.status == PostStatus.trash) post.status = PostStatus.draft;
    final body = _postToJson(post,
        publish: publish, tagIds: await _resolveTagIds(post.tags));
    final data = await _request(
        'POST', '/wp/v2/${post.isPage ? 'pages' : 'posts'}',
        body: body, timeout: _saveTimeout);
    return _postFromJson(data as Map, isPage: post.isPage);
  }

  Future<BlogPost> editPost(BlogPost post, {required bool publish}) async {
    final body = _postToJson(post,
        publish: publish, tagIds: await _resolveTagIds(post.tags));
    final data = await _request(
        'POST', '/wp/v2/${post.isPage ? 'pages' : 'posts'}/${post.id}',
        body: body, timeout: _saveTimeout);
    return _postFromJson(data as Map, isPage: post.isPage);
  }

  /// Changes ONLY the post status — used by dashboard quick actions so a
  /// "publish" / "move to draft" tap can't clobber concurrent edits made
  /// elsewhere (the full editPost payload is last-write-wins).
  ///
  /// [date] accompanies a scheduled (future) transition: WordPress needs
  /// a future date to keep status=future, otherwise it publishes now.
  Future<bool> editPostStatus(String id, PostStatus status,
      {bool isPage = false, DateTime? date}) async {
    await _request('POST', '/wp/v2/${isPage ? 'pages' : 'posts'}/$id',
        body: {
          'status': status.wpValue,
          if (date != null) 'date': date.toUtc().toIso8601String(),
        },
        timeout: _saveTimeout);
    return true;
  }

  /// Resolves the editor's mixed tag input (numeric ids from loaded posts,
  /// plain names typed by the user) into tag ids. Unknown names are created
  /// via POST /wp/v2/tags; creation failures (permissions) degrade by
  /// dropping that tag instead of failing the whole save.
  Future<List<int>> _resolveTagIds(List<String> tags) async {
    if (tags.isEmpty) return const [];
    final ids = <int>[];
    final names = <String>[];
    for (final tag in tags) {
      final asInt = int.tryParse(tag);
      if (asInt != null) {
        ids.add(asInt);
      } else {
        names.add(tag);
      }
    }
    if (names.isEmpty) return ids;

    if (_tagCache == null) {
      try {
        _tagCache = await getTags();
      } catch (_) {
        _tagCache = const [];
      }
    }
    final byName = <String, int>{
      for (final t in _tagCache!)
        if (int.tryParse(t.id) != null) t.name.toLowerCase(): int.parse(t.id),
    };
    for (final name in names) {
      final existing = byName[name.toLowerCase()];
      if (existing != null) {
        ids.add(existing);
        continue;
      }
      try {
        final created =
            await _request('POST', '/wp/v2/tags', body: {'name': name});
        final id = int.tryParse('${created['id']}');
        if (id != null) {
          ids.add(id);
          _tagCache = [..._tagCache!, PostTag(id: '$id', name: name)];
        }
      } catch (_) {
        // Cannot create this tag (role limits) — skip it.
      }
    }
    return ids;
  }

  Future<bool> deletePost(String id, {bool isPage = false}) async {
    // No force param: WordPress moves the post to trash, matching the
    // "move to trash" semantics of wp.deletePost in XML-RPC.
    await _request('DELETE', '/wp/v2/${isPage ? 'pages' : 'posts'}/$id',
        timeout: _saveTimeout);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Categories & tags
  // ---------------------------------------------------------------------------

  Future<List<PostCategory>> getCategories() async {
    final data = await _request('GET', '/wp/v2/categories',
        query: {'per_page': '100', 'orderby': 'count', 'order': 'desc'});
    if (data is! List) return const [];
    return data
        .map((raw) => PostCategory(
              id: '${raw['id']}',
              name: '${raw['name']}',
              parentId: raw['parent'] == null || raw['parent'] == 0
                  ? null
                  : '${raw['parent']}',
              slug: raw['slug'] == null ? null : '${raw['slug']}',
            ))
        .toList();
  }

  Future<PostCategory> newCategory(String name,
      {String? parentId, String? slug}) async {
    final data = await _request('POST', '/wp/v2/categories', body: {
      'name': name,
      'slug': ?slug,
      if (parentId != null && parentId != '0') 'parent': int.tryParse(parentId),
    });
    return PostCategory(
        id: '${data['id']}', name: '${data['name']}', slug: '${data['slug']}');
  }

  Future<List<PostTag>> getTags() async {
    final data = await _request('GET', '/wp/v2/tags',
        query: {'per_page': '100', 'orderby': 'count', 'order': 'desc'});
    if (data is! List) return const [];
    return data
        .map((raw) => PostTag(
              id: '${raw['id']}',
              name: '${raw['name']}',
              slug: raw['slug'] == null ? null : '${raw['slug']}',
            ))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Media
  // ---------------------------------------------------------------------------

  /// POST /wp/v2/media (multipart upload).
  Future<MediaUploadResult> uploadMedia(
      String filename, List<int> bytes, String mimeType) async {
    final uri = Uri.parse('$baseUrl/wp/v2/media');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(await _headers())
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename,
          contentType: http.MediaType.parse(mimeType)));
    // Media uploads need a much longer budget than regular API calls
    // (cross-border transfer + server-side image re-encoding).
    final res = await _http
        .send(request)
        .timeout(const Duration(minutes: 5));
    final response = await http.Response.fromStream(res);
    if (response.statusCode >= 400) {
      throw WordPressRestException(
          response.statusCode, 'media_upload_failed', response.body);
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    return MediaUploadResult(
      id: '${data['id']}',
      url: (data['source_url'] as String?) ?? '',
      file: (data['source_url'] as String?) ?? '',
      type: mimeType,
    );
  }

  // ---------------------------------------------------------------------------
  // Settings & site info
  // ---------------------------------------------------------------------------

  /// GET /wp/v2/settings — blog title, description, etc.
  Future<Map<String, dynamic>> getSettings() async {
    final data = await _request('GET', '/wp/v2/settings');
    return data is Map<String, dynamic> ? data : const {};
  }

  /// GET /wp-json — index document (site name, namespaces, URLs).
  Future<Map<String, dynamic>> getSiteIndex() async {
    final data = await _request('GET', '');
    return data is Map<String, dynamic> ? data : const {};
  }

  /// Releases the underlying HTTP client. Must be called when the owning
  /// BlogService is discarded (account switch/removal), or every switch
  /// leaks a connection pool.
  void close() => _http.close();

  // ---------------------------------------------------------------------------
  // JSON <-> model mapping
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _postToJson(BlogPost post,
      {required bool publish, List<int>? tagIds}) {
    // publish=false means "Save draft"; publish=true sends the chosen
    // status verbatim (EditorState applies the draft → publish default).
    final status = publish ? post.status : PostStatus.draft;
    return {
      'title': post.title,
      'content': post.content,
      'excerpt': post.excerpt,
      'status': status.wpValue,
      // Scheduled publishing rides the date field; without it WordPress
      // ignores the future date and publishes immediately.
      if (post.datePublished != null)
        'date': post.datePublished!.toUtc().toIso8601String(),
      if (post.slug?.isNotEmpty == true) 'slug': post.slug,
      if (post.password?.isNotEmpty == true) 'password': post.password,
      if (!post.isPage) ...{
        'categories': post.categories.map(int.tryParse).whereType<int>().toList(),
        // tagIds comes from _resolveTagIds (names created/looked up);
        // fall back to numeric-only when resolution was skipped.
        'tags': tagIds ?? post.tags.map(int.tryParse).whereType<int>().toList(),
      },
      if (post.isPage) ...{
        if (post.pageParentId?.isNotEmpty == true)
          'parent': int.tryParse(post.pageParentId!),
        if (post.pageOrder != null) 'menu_order': post.pageOrder,
      },
    };
  }

  /// Picks editable content: prefer `raw` (edit context), fall back to
  /// `rendered` when raw is missing or empty (common on list endpoints).
  static String _pickContent(dynamic c) {
    if (c is Map) {
      final raw = c['raw'];
      if (raw is String && raw.trim().isNotEmpty) return raw;
      final rendered = c['rendered'];
      if (rendered is String && rendered.isNotEmpty) return rendered;
      return '';
    }
    return c == null ? '' : '$c';
  }

  BlogPost _postFromJson(Map raw, {bool isPage = false}) {
    // date_gmt carries no timezone suffix — DateTime.parse would read it
    // as LOCAL time and shift every displayed date by the UTC offset.
    DateTime? parseDate(dynamic raw) {
      if (raw is! String || raw.isEmpty) return null;
      final hasTz = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
      return DateTime.tryParse(hasTz ? raw : '${raw}Z');
    }

    final status = PostStatus.fromWp('${raw['status'] ?? 'draft'}');
    return BlogPost(
      id: '${raw['id'] ?? ''}',
      title: (raw['title'] is Map
              ? '${raw['title']['raw'] ?? raw['title']['rendered']}'
              : '${raw['title'] ?? ''}')
          .trim(),
      content: _pickContent(raw['content']),
      excerpt: raw['excerpt'] is Map
          ? '${raw['excerpt']['raw'] ?? raw['excerpt']['rendered'] ?? ''}'
          : '${raw['excerpt'] ?? ''}',
      slug: raw['slug'] == null || '${raw['slug']}'.isEmpty ? null : '${raw['slug']}',
      permalink: raw['link'] == null ? null : '${raw['link']}',
      status: status,
      isPage: isPage,
      authorId: raw['author'] == null ? null : '${raw['author']}',
      dateCreated: parseDate(raw['date_gmt']),
      datePublished: parseDate(raw['date_gmt']),
      commentsEnabled: '${raw['comment_status'] ?? 'open'}' == 'open',
      pingsEnabled: '${raw['ping_status'] ?? 'open'}' == 'open',
      categories: (raw['categories'] as List?)
              ?.map((c) => '$c')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      tags: (raw['tags'] as List?)?.map((t) => '$t').toList() ?? const [],
    );
  }
}
