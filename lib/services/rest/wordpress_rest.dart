import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/blog.dart';
import '../../models/blog_post.dart';
import '../post_meta.dart';

/// Exception carrying HTTP status + REST API error payload.
class WordPressRestException implements Exception {
  WordPressRestException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'WordPress REST error $statusCode ($code): $message';
}

/// Internal marker thrown to trigger a single JWT re-auth + retry (P-03).
class _JwtRetry implements Exception {}

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
  }) : _http = httpClient ?? http.Client() {
    // S1: warn (debug only) when credentials and post bodies will travel
    // over plaintext HTTP. XML-RPC/REST auth is Basic/Bearer, so an http
    // endpoint exposes the password on the wire.
    if (!baseUrl.startsWith('https://') && kDebugMode) {
      debugPrint(
        'WARNING: WordPress REST endpoint "$baseUrl" is not HTTPS — '
        'credentials and post content will be sent in cleartext.',
      );
    }
  }

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

  /// Bound on each list fetch. The status-degrade chain can issue several
  /// serial requests; a normal 30s budget would let a slow/unreachable
  /// server block the dashboard for minutes. 10s keeps the worst case for a
  /// restricted role tolerable (P-10).
  static const _listTimeout = Duration(seconds: 10);

  /// Last status query the server accepted for getPosts, per content type.
  /// Reused on the next refresh so the degrade chain isn't re-walked, and
  /// kept separate for posts vs pages (P-15). Per-instance (not static): the
  /// same BlogService keeps its client for the whole session, so normal
  /// refreshes already benefit; only an account switch rebuilds it, and the
  /// bounded [_listTimeout] makes that single re-walk cheap.
  String? _workingStatusQuery;
  String? _workingStatusQueryPages;

  static const _timeout = Duration(seconds: 30);

  /// Cap on response bytes. REST payloads are small JSON; an unbounded body
  /// lets a malicious or broken server exhaust memory with a huge response
  /// (P-08 — mirrors the XML-RPC cap in [XmlRpcClient]).
  static const _maxResponseBytes = 16 * 1024 * 1024; // 16 MiB

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Detects the REST root for a WordPress site.
  /// Mirrors RSD discovery: HEAD/GET the homepage, read the
  /// `Link: <https://site/wp-json/>; rel="https://api.w.org/"` header.
  static Future<String?> discoverRestRoot(
    String homepageUrl, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse(homepageUrl);
      http.Response? res;
      try {
        res = await httpClient.head(uri).timeout(_timeout);
      } catch (_) {
        /* fall through to GET */
      }
      res ??= await httpClient.get(uri).timeout(_timeout);
      final link = res.headers['link'];
      if (link != null) {
        final m = RegExp(
          r'<([^>]+)>;\s*rel="https://api\.w\.org/"',
        ).firstMatch(link);
        if (m != null) return m.group(1)!.replaceAll(RegExp(r'/+$'), '');
      }
      // Fallback: probe the default location.
      final probe = await httpClient
          .get(
            Uri.parse('${homepageUrl.replaceAll(RegExp(r'/+$'), '')}/wp-json/'),
          )
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

  Future<Map<String, String>> _headers({
    Map<String, String> extra = const {},
  }) async {
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
        _jwtToken ??= await (_jwtFuture ??= _fetchJwtToken().whenComplete(
          () => _jwtFuture = null,
        ));
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
      res.statusCode,
      'jwt_auth_failed',
      'JWT authentication failed',
    );
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
    // One attempt: build headers (re-fetching the JWT when invalidated),
    // send, read the (size-capped) body, then surface errors.
    var jwtRetried = false;
    Future<dynamic> attempt() async {
      final uri = Uri.parse(
        '$baseUrl$path',
      ).replace(queryParameters: query == null || query.isEmpty ? null : query);
      final headers = await _headers(
        extra: {
          if (body != null) 'Content-Type': 'application/json',
          ...extraHeaders,
        },
      );
      // Never attach a body to GET/DELETE requests — some WAFs (Cloudflare,
      // BT panel…) reject non-empty or zero-length bodies on GET/DELETE with
      // 403. DELETE also must not carry a body (RFC 7231).
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null &&
          method.toUpperCase() != 'GET' &&
          method.toUpperCase() != 'DELETE') {
        request.body = jsonEncode(body);
      }
      final res = await _http.send(request).timeout(timeout ?? _timeout);
      final bytes = await _readCapped(res, _maxResponseBytes);
      final response = http.Response(
        utf8.decode(bytes),
        res.statusCode,
        headers: res.headers,
      );

      if (response.statusCode >= 400) {
        String code = 'http_error';
        String message = response.reasonPhrase ?? 'Request failed';
        try {
          final err = jsonDecode(utf8.decode(response.bodyBytes));
          if (err is Map) {
            code = '${err['code'] ?? code}';
            message = '${err['message'] ?? message}';
          }
        } catch (_) {
          /* keep defaults */
        }
        // JWT tokens can expire (401) or be rejected as invalid (403) —
        // clear it so the retry re-authenticates instead of failing every
        // call until the app is restarted (P-03).
        if (authMethod == RestAuthMethod.jwt &&
            !jwtRetried &&
            (response.statusCode == 401 || response.statusCode == 403)) {
          _jwtToken = null;
          jwtRetried = true;
          throw _JwtRetry();
        }
        throw WordPressRestException(response.statusCode, code, message);
      }
      if (response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }

    try {
      return await attempt();
    } on _JwtRetry {
      // One transparent retry after invalidating the expired JWT.
      return await attempt();
    }
  }

  /// Reads a streamed response into bytes, aborting (before fully buffering)
  /// once it exceeds [maxBytes]. Guards against a malicious or broken server
  /// exhausting memory with a huge response (P-08).
  Future<Uint8List> _readCapped(http.StreamedResponse res, int maxBytes) async {
    final out = <int>[];
    var total = 0;
    await for (final chunk in res.stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw WordPressRestException(
          413,
          'response_too_large',
          'Response exceeds $maxBytes bytes',
        );
      }
      out.addAll(chunk);
    }
    return Uint8List.fromList(out);
  }

  // ---------------------------------------------------------------------------
  // Users
  // ---------------------------------------------------------------------------

  /// GET /wp/v2/users/me — validates credentials and returns the profile.
  Future<Map<String, dynamic>> getProfile() async {
    final data = await _request(
      'GET',
      '/wp/v2/users/me',
      query: {'context': 'edit'},
    );
    if (data is Map<String, dynamic>) return data;
    throw WordPressRestException(500, 'invalid_profile', 'Bad profile payload');
  }

  /// Fetches a REST collection endpoint across every page.
  ///
  /// WordPress caps `per_page` at 100, so a single request silently truncates
  /// blogs with more than 100 categories/tags/authors. We page with `page`
  /// until a page returns fewer than a full page (or empty), matching the
  /// all-items behaviour XML-RPC already gives for `wp.getCategories` /
  /// `wp.getTags` / `wp.getAuthors`. A page ceiling guards against a server
  /// that never returns a short page.
  static const int _listPageSize = 100;
  static const int _listMaxPages = 100; // 10k-item safety ceiling.

  Future<List<Map<String, dynamic>>> _fetchAllPages(
    String path, {
    Map<String, String> extraQuery = const {},
  }) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= _listMaxPages; page++) {
      final data = await _request('GET', path, query: {
        'per_page': '$_listPageSize',
        'page': '$page',
        ...extraQuery,
      });
      if (data is! List || data.isEmpty) break;
      out.addAll(data.cast<Map<String, dynamic>>());
      if (data.length < _listPageSize) break;
    }
    return out;
  }

  /// GET /wp/v2/users — lists blog authors for the multi-author picker
  /// (P3-14). `context=view` is enough for id/name/slug and avoids 401 on
  /// sites where the current role can't read `edit` context. Paged so a site
  /// with >100 authors is fully enumerated (P3-16).
  Future<List<BlogAuthor>> getAuthors() async {
    final rows = await _fetchAllPages(
      '/wp/v2/users',
      extraQuery: {'context': 'view'},
    );
    return rows.map((m) {
      final id = '${m['id']}';
      final name = '${m['name'] ?? m['slug'] ?? ''}';
      final slug = m['slug'] == null ? null : '${m['slug']}';
      return BlogAuthor(id: id, name: name, slug: slug);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Posts & pages
  // ---------------------------------------------------------------------------

  Future<List<BlogPost>> getPosts({
    int perPage = 30,
    int page = 1,
    int offset = 0,
    bool pages = false,
    PostStatus? status,
    String search = '',
    List<String>? fields,
  }) async {
    Future<List<BlogPost>> fetch(String statuses, {Duration? timeout}) async {
      // P-09: REST field projection — drop the heavy `content` body from list
      // responses. The dashboard shows only title/excerpt/date/categories;
      // crash recovery and offline copies fetch full content via getPost().
      final query = <String, String>{
        'context': 'edit',
        'per_page': '$perPage',
        // P1-5: `offset` drives infinite scroll. When set it takes precedence
        // over `page`; for the first page (offset 0) we keep the default paging.
        if (offset > 0) 'offset': '$offset' else 'page': '$page',
        'status': statuses,
        if (search.isNotEmpty) 'search': search,
        if (fields != null) '_fields': fields.join(','),
      };
      final data = await _request(
        'GET',
        '/wp/v2/${pages ? 'pages' : 'posts'}',
        query: query,
        timeout: timeout,
      );
      if (data is! List) return const [];
      return data
          .map((raw) => _postFromJson(raw as Map, isPage: pages))
          .toList();
    }

    // Cache key isolates posts from pages so a cached query for one type is
    // never reused on the other (P-15).
    final cached = pages ? _workingStatusQueryPages : _workingStatusQuery;

    // Without an explicit status the REST API only returns 'publish'.
    // Request every editable status first so drafts show up, but degrade
    // gracefully: roles without permission for private/future statuses get
    // the WHOLE request rejected (rest_invalid_status / rest_forbidden),
    // which used to leave the dashboard permanently empty.
    final explicit = status?.wpValue;
    if (explicit != null) {
      // An explicit status was requested (e.g. a role-restricted filter).
      // If the server rejects it (rest_invalid_status / rest_forbidden is
      // common for 'private' without read_private_posts), degrade through
      // the same multi-tier chain instead of failing the whole fetch (R4).
      try {
        return await fetch(explicit, timeout: _listTimeout);
      } on WordPressRestException catch (e) {
        if (e.statusCode != 400 && e.statusCode != 401 && e.statusCode != 403) {
          rethrow;
        }
      }
      // Fall through to the degrade chain below.
    }

    // Reuse the last query this endpoint accepted; probe it first.
    if (cached != null) {
      try {
        return await fetch(cached, timeout: _listTimeout);
      } on WordPressRestException catch (e) {
        if (e.statusCode != 400 && e.statusCode != 401 && e.statusCode != 403) {
          rethrow;
        }
        if (pages) {
          _workingStatusQueryPages = null;
        } else {
          _workingStatusQuery = null;
        }
      }
    }
    for (final query in const [
      'publish,draft,future,pending,private,trash',
      // WordPress authorizes the WHOLE status list at once: a role without
      // read_private_posts (e.g. Author) gets 401 for any query containing
      // 'private'. Degrading straight to 'publish,draft,pending' also lost
      // future/trash — scheduled posts became invisible even though the
      // site shows them. The no-private tier keeps future/trash for such
      // roles; only truly read-only access falls through further.
      'publish,draft,future,pending,trash',
      'publish,draft,future,pending,private',
      'publish,draft,pending',
      'publish',
    ]) {
      try {
        final result = await fetch(query, timeout: _listTimeout);
        if (pages) {
          _workingStatusQueryPages = query;
        } else {
          _workingStatusQuery = query;
        }
        return result;
      } on WordPressRestException catch (e) {
        if (e.statusCode != 400 && e.statusCode != 401 && e.statusCode != 403) {
          rethrow;
        }
      }
    }
    // Unreachable: the last query ('publish') is always accepted.
    return fetch('publish', timeout: _listTimeout);
  }

  Future<BlogPost> getPost(String id, {bool isPage = false}) async {
    Future<BlogPost> fetch(String context) async {
      final data = await _request(
        'GET',
        '/wp/v2/${isPage ? 'pages' : 'posts'}/$id',
        query: {'context': context},
      );
      // C1: an empty/non-object body (e.g. a 200 with no JSON) would throw a
      // cryptic CastError on `data as Map` — surface a typed exception.
      if (data is! Map) {
        throw WordPressRestException(
          500,
          'invalid_post',
          'Bad post payload for id $id',
        );
      }
      return _postFromJson(data, isPage: isPage);
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
    // rest_invalid_param. Compute the effective status LOCALLY (R5) — never
    // mutate [post], or the caller's in-memory draft (e.g. an offline copy)
    // would be silently downgraded to draft.
    final effectiveStatus = post.status == PostStatus.trash
        ? PostStatus.draft
        : post.status;
    final body = _postToJson(
      post,
      publish: publish,
      effectiveStatus: effectiveStatus,
      tagIds: await _resolveTagIds(post.tags),
    );
    final data = await _request(
      'POST',
      '/wp/v2/${post.isPage ? 'pages' : 'posts'}',
      body: body,
      timeout: _saveTimeout,
    );
    // C1: a successful create still returns the new post object; an empty
    // body would crash on `data as Map`.
    if (data is! Map) {
      throw WordPressRestException(
        500,
        'invalid_post',
        'Empty response creating post',
      );
    }
    return _postFromJson(data, isPage: post.isPage);
  }

  Future<BlogPost> editPost(BlogPost post, {required bool publish}) async {
    final body = _postToJson(
      post,
      publish: publish,
      effectiveStatus: post.status,
      tagIds: await _resolveTagIds(post.tags),
    );
    final data = await _request(
      'POST',
      '/wp/v2/${post.isPage ? 'pages' : 'posts'}/${post.id}',
      body: body,
      timeout: _saveTimeout,
    );
    // C1: empty body on a successful edit would crash on `data as Map`.
    if (data is! Map) {
      throw WordPressRestException(
        500,
        'invalid_post',
        'Empty response editing post ${post.id}',
      );
    }
    return _postFromJson(data, isPage: post.isPage);
  }

  /// Changes ONLY the post status — used by dashboard quick actions so a
  /// "publish" / "move to draft" tap can't clobber concurrent edits made
  /// elsewhere (the full editPost payload is last-write-wins).
  ///
  /// [date] accompanies a scheduled (future) transition: WordPress needs
  /// a future date to keep status=future, otherwise it publishes now.
  Future<bool> editPostStatus(
    String id,
    PostStatus status, {
    bool isPage = false,
    DateTime? date,
  }) async {
    await _request(
      'POST',
      '/wp/v2/${isPage ? 'pages' : 'posts'}/$id',
      body: {
        'status': status.wpValue,
        if (date != null) 'date': date.toUtc().toIso8601String(),
      },
      timeout: _saveTimeout,
    );
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
    // P-05: known names resolve from the cache immediately.
    for (final name in names) {
      final existing = byName[name.toLowerCase()];
      if (existing != null) ids.add(existing);
    }
    // P-05: unknown names are created in parallel (independent) and any that
    // fail or return an empty payload are skipped instead of crashing.
    final unknown = names
        .where((n) => !byName.containsKey(n.toLowerCase()))
        .toList();
    if (unknown.isNotEmpty) {
      final created = await Future.wait(unknown.map(_createTag));
      final newTags = <PostTag>[];
      for (var i = 0; i < unknown.length; i++) {
        final id = created[i];
        if (id != null) {
          ids.add(id);
          newTags.add(PostTag(id: '$id', name: unknown[i]));
        }
      }
      if (newTags.isNotEmpty) _tagCache = [..._tagCache!, ...newTags];
    }
    return ids;
  }

  /// Creates a single tag by name. Returns its id, or null when the server
  /// rejects the creation (role limits) or returns an empty/invalid payload
  /// (P-05 — replaces the previous crash-on-null behavior).
  Future<int?> _createTag(String name) async {
    try {
      final created = await _request(
        'POST',
        '/wp/v2/tags',
        body: {'name': name},
      );
      if (created is! Map) return null;
      return int.tryParse('${created['id']}');
    } catch (_) {
      // Cannot create this tag (role limits) — skip it.
    }
    return null;
  }

  Future<bool> deletePost(String id, {bool isPage = false}) async {
    // No force param: WordPress moves the post to trash, matching the
    // "move to trash" semantics of wp.deletePost in XML-RPC.
    await _request(
      'DELETE',
      '/wp/v2/${isPage ? 'pages' : 'posts'}/$id',
      timeout: _saveTimeout,
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Categories & tags
  // ---------------------------------------------------------------------------

  /// Paged so a site with >100 categories is fully enumerated (P3-16).
  Future<List<PostCategory>> getCategories() async {
    final rows = await _fetchAllPages(
      '/wp/v2/categories',
      extraQuery: {'orderby': 'count', 'order': 'desc'},
    );
    return rows
        .map(
          (raw) => PostCategory(
            id: '${raw['id']}',
            name: '${raw['name']}',
            parentId: raw['parent'] == null || raw['parent'] == 0
                ? null
                : '${raw['parent']}',
            slug: raw['slug'] == null ? null : '${raw['slug']}',
          ),
        )
        .toList();
  }

  Future<PostCategory> newCategory(
    String name, {
    String? parentId,
    String? slug,
  }) async {
    final data = await _request(
      'POST',
      '/wp/v2/categories',
      body: {
        'name': name,
        'slug': ?slug,
        if (parentId != null && parentId != '0')
          'parent': int.tryParse(parentId),
      },
    );
    // P-01: an empty/non-object response would crash on `data['id']`.
    if (data is! Map) {
      throw WordPressRestException(
        500,
        'invalid_category',
        'Bad category payload for "$name"',
      );
    }
    return PostCategory(
      id: '${data['id']}',
      name: '${data['name']}',
      slug: '${data['slug']}',
    );
  }

  /// Paged so a site with >100 tags is fully enumerated (P3-16).
  Future<List<PostTag>> getTags() async {
    final rows = await _fetchAllPages(
      '/wp/v2/tags',
      extraQuery: {'orderby': 'count', 'order': 'desc'},
    );
    final tags = rows
        .map(
          (raw) => PostTag(
            id: '${raw['id']}',
            name: '${raw['name']}',
            slug: raw['slug'] == null ? null : '${raw['slug']}',
          ),
        )
        .toList();
    // R3: keep the name→id resolution cache warm so a later save resolves
    // existing tags from memory instead of re-querying; created tags are
    // appended incrementally in [_resolveTagIds].
    _tagCache = tags;
    return tags;
  }

  // ---------------------------------------------------------------------------
  // Media
  // ---------------------------------------------------------------------------

  /// POST /wp/v2/media (multipart upload).
  Future<MediaUploadResult> uploadMedia(
    String filename,
    List<int> bytes,
    String mimeType,
  ) async {
    final uri = Uri.parse('$baseUrl/wp/v2/media');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(await _headers())
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: http.MediaType.parse(mimeType),
        ),
      );
    // Media uploads need a much longer budget than regular API calls
    // (cross-border transfer + server-side image re-encoding).
    final res = await _http.send(request).timeout(const Duration(minutes: 5));
    // P-08: read the response stream with a byte cap (do NOT name this
    // `bytes` — that collides with the [bytes] upload-content parameter).
    final responseBytes = await _readCapped(res, _maxResponseBytes);
    final response = http.Response(
      utf8.decode(responseBytes),
      res.statusCode,
      headers: res.headers,
    );
    if (response.statusCode >= 400) {
      throw WordPressRestException(
        response.statusCode,
        'media_upload_failed',
        response.body,
      );
    }
    // P-02: a 200 with an empty/invalid body must not crash with a cryptic
    // FormatException / TypeError — surface a typed error instead.
    final bodyText = utf8.decode(response.bodyBytes);
    if (bodyText.isEmpty) {
      throw WordPressRestException(
        response.statusCode,
        'media_upload_failed',
        'Empty media response',
      );
    }
    final data = jsonDecode(bodyText);
    if (data is! Map) {
      throw WordPressRestException(
        response.statusCode,
        'media_upload_failed',
        'Invalid media response',
      );
    }
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

  Map<String, dynamic> _postToJson(
    BlogPost post, {
    required bool publish,
    required PostStatus effectiveStatus,
    List<int>? tagIds,
  }) {
    // Send the effective status verbatim. A "save draft" (publish=false)
    // now honors an explicit non-draft status the user selected (e.g.
    // "pending review") instead of always reverting to draft (C3); the
    // trash→draft downgrade was already applied to a LOCAL copy (R5), so
    // [post] is never mutated here.
    final status = effectiveStatus;
    // P3-14: SEO / social metadata (Yoast-compatible). Computed up front so
    // it can be conditionally included; only non-empty maps are sent so an
    // untouched post never overwrites server SEO values.
    final meta = buildPostMeta(post);
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
      if (meta.isNotEmpty) 'meta': meta,
      // P3-14: multi-author — only send when explicitly set, so posts left
      // at the server default author aren't overwritten on every save.
      if (post.authorId?.isNotEmpty == true) 'author': post.authorId,
      if (!post.isPage) ...{
        'categories': post.categories
            .map(int.tryParse)
            .whereType<int>()
            .toList(),
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
      final hasTz =
          raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
      return DateTime.tryParse(hasTz ? raw : '${raw}Z');
    }

    final status = PostStatus.fromWp('${raw['status'] ?? 'draft'}');
    return BlogPost(
      id: '${raw['id'] ?? ''}',
      title:
          (raw['title'] is Map
                  ? '${raw['title']['raw'] ?? raw['title']['rendered']}'
                  : '${raw['title'] ?? ''}')
              .trim(),
      content: _pickContent(raw['content']),
      excerpt: raw['excerpt'] is Map
          ? '${raw['excerpt']['raw'] ?? raw['excerpt']['rendered'] ?? ''}'
          : '${raw['excerpt'] ?? ''}',
      slug: raw['slug'] == null || '${raw['slug']}'.isEmpty
          ? null
          : '${raw['slug']}',
      // P3-14: round-trip SEO metadata so a background full-content fetch
      // (which the editor uses to refresh the open post) keeps the values
      // the user already set, rather than wiping them.
      seoTitle: readRestMeta(raw['meta'], PostMetaKeys.seoTitle),
      seoDescription: readRestMeta(raw['meta'], PostMetaKeys.seoDescription),
      ogImageUrl: readRestMeta(raw['meta'], PostMetaKeys.ogImage),
      permalink: raw['link'] == null ? null : '${raw['link']}',
      status: status,
      isPage: isPage,
      authorId: raw['author'] == null ? null : '${raw['author']}',
      dateCreated: parseDate(raw['date_gmt']),
      datePublished: parseDate(raw['date_gmt']),
      modified: parseDate(raw['modified_gmt']),
      commentsEnabled: '${raw['comment_status'] ?? 'open'}' == 'open',
      pingsEnabled: '${raw['ping_status'] ?? 'open'}' == 'open',
      categories:
          (raw['categories'] as List?)
              ?.map((c) => '$c')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      tags: (raw['tags'] as List?)?.map((t) => '$t').toList() ?? const [],
    );
  }
}
