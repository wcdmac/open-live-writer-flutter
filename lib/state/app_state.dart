import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/blog.dart';
import '../models/blog_post.dart';
import '../utils/constants.dart';
import '../services/account_store.dart';
import '../services/blog_service.dart';
import '../services/error_message.dart';
import '../services/local_draft_store.dart';
import '../services/media_cache.dart';
import '../services/theme_detector.dart';

/// Root application state: accounts, the active account, its taxonomies
/// and post list. Backed by [AccountStore] for persistence.
class AppState extends ChangeNotifier {
  AppState({AccountStore? store})
      : store = store ?? AccountStore(),
        drafts = LocalDraftStore();

  final AccountStore store;
  final LocalDraftStore drafts;

  List<BlogAccount> accounts = [];
  BlogAccount? currentAccount;
  BlogService? _service;
  String? _currentPassword;

  List<PostCategory> categories = [];
  List<PostTag> tags = [];
  List<BlogAuthor> authors = [];
  List<BlogPost> posts = [];
  List<LocalDraft> localDrafts = [];
  BlogTheme? theme;

  /// App-wide color scheme preference (P3-15). Defaults to following the
  /// OS setting so behavior is unchanged for users who never open the
  /// preference; persisted via SharedPreferences so it survives restarts.
  ThemeMode themeMode = ThemeMode.system;
  bool loading = false;
  bool loadingMore = false;
  bool canLoadMore = false;
  String? error;

  /// Number of posts already loaded for the current dashboard page (P1-5).
  /// `loadMorePosts` fetches the next slice at `_postOffset + kPostPageSize`.
  int _postOffset = 0;

  /// Account whose theme was already probed in this session — theme
  /// detection is one HTTP round-trip per homepage; retrying it on every
  /// refresh when the cached theme is "Default" just burns traffic.
  String? _themeProbedFor;

  bool get hasAccount => currentAccount != null;

  BlogService? get service => _service;

  @override
  void dispose() {
    // Release the HTTP connection pool owned by the active BlogService.
    // Without this, disposing the provider (hot restart, teardown) leaked the
    // underlying http.Client — it was only ever closed on account switch.
    _service?.dispose();
    _service = null;
    super.dispose();
  }

  Future<void> load() async {
    try {
      accounts = await store.loadAccounts();
      if (accounts.isNotEmpty) {
        final prefs = await store.prefs;
        themeMode = _themeModeFromString(prefs.getString('olw.themeMode'));
        final savedCurrentId = prefs.getString('olw.currentAccount');
        currentAccount = accounts.firstWhere(
          (a) => a.id == savedCurrentId,
          orElse: () => accounts.first,
        );
        await _connectCurrent();
        await _loadLocalDrafts();
        notifyListeners();
        // Auto-load the post list on startup. HomePage's post-frame callback
        // alone races with this async load and can miss the refresh entirely,
        // leaving the list permanently empty.
        await refresh();
      } else {
        notifyListeners();
      }
    } catch (e, stack) {
      // Previously this bubbled out as an unhandled async error: the app
      // stayed on a blank screen with no indication of what failed.
      // Details go to the log; the UI gets a stable, non-leaky message.
      debugPrint('AppState.load failed: $e\n$stack');
      error = 'Startup failed. Please restart the app.';
      notifyListeners();
    }
  }

  Future<void> selectAccount(BlogAccount account) async {
    currentAccount = account;
    (await store.prefs).setString('olw.currentAccount', account.id);
    await _connectCurrent();
    await _loadLocalDrafts();
    notifyListeners();
    // Reload the dashboard: the previously visible posts/categories/tags
    // belong to the account that was just switched away from.
    await refresh();
  }

  Future<void> _connectCurrent() async {
    final account = currentAccount;
    // Replace the service cleanly: disposing releases the old HTTP
    // connection pool instead of leaking one per switch.
    _service?.dispose();
    _service = null;
    _themeProbedFor = null;
    theme = null;
    if (account == null) return;
    _currentPassword = await store.loadPassword(account.id);
    if (_currentPassword == null || _currentPassword!.isEmpty) {
      error = 'No stored credentials for ${account.name}. '
          'Please remove and re-add the account.';
      return;
    }
    _service = BlogService(account, _currentPassword!);
    theme = await store.loadTheme(account.id);
  }

  Future<void> addAccount(BlogAccount account, String password) async {
    await store.addAccount(account, password);
    accounts = await store.loadAccounts();
    await selectAccount(account);
  }

  Future<void> removeAccount(String accountId) async {
    await store.removeAccount(accountId);
    accounts = await store.loadAccounts();
    if (currentAccount?.id == accountId) {
      currentAccount = accounts.isEmpty ? null : accounts.first;
      await _connectCurrent();
      // The on-screen lists belong to the removed account — drop them
      // and reload for whichever account (if any) becomes current.
      posts = [];
      categories = [];
      tags = [];
      authors = [];
      error = null;
      await _loadLocalDrafts();
      // refresh() already notifies in its finally block, so a single
      // notify here (when the removed account was current) avoids the
      // redundant double notifyListeners the old code produced.
      if (currentAccount != null) await refresh();
    } else {
      notifyListeners();
    }
  }

  Future<void> updateAccount(BlogAccount account) async {
    await store.updateAccount(account);
    accounts = await store.loadAccounts();
    if (currentAccount?.id == account.id) {
      currentAccount = account;
      await _connectCurrent();
      await refresh();
    }
    notifyListeners();
  }

  /// Reloads taxonomies, theme and post list for the current account.
  ///
  /// The three network calls are deliberately independent: a failing
  /// tags/categories endpoint (plugin conflicts, role permissions, WAF)
  /// must never prevent the post list from loading — bundling them with
  /// Future.wait made the whole dashboard appear permanently empty.
  Future<void> refresh() async {
    final svc = _service;
    final account = currentAccount;
    // The account can be removed mid-flight (this method awaits several
    // network calls); snapshot it instead of assuming currentAccount!.
    if (svc == null || account == null) return;
    // Re-entrancy guard: a rapid double-tap on refresh (or overlapping
    // refresh() calls from selectAccount/addAccount) would otherwise run
    // two concurrent fetches and duplicate the theme probe.
    if (loading) return;
    loading = true;
    error = null;
    loadingMore = false;
    _postOffset = 0;
    notifyListeners();

    // Taxonomies are best-effort; failures degrade silently.
    final catsFuture = svc.getCategories().catchError((Object e) {
      debugPrint('getCategories failed: $e');
      return <PostCategory>[];
    });
    final tagsFuture = svc.getTags().catchError((Object e) {
      debugPrint('getTags failed: $e');
      return <PostTag>[];
    });
    // P3-14 multi-author: author list for the settings-sheet picker. Best-
    // effort — servers without wp.getAuthors / users endpoint just leave the
    // picker hidden rather than failing the dashboard load.
    final authorsFuture = svc.getAuthors().catchError((Object e) {
      debugPrint('getAuthors failed: $e');
      return <BlogAuthor>[];
    });
    // Theme probe runs concurrently with the list load (P1-5): it used to
    // wait for the whole post list first, adding a full extra round-trip to
    // every refresh. Non-fatal, so a failure just returns the current theme.
    final themeFuture = _probeTheme(account, svc);

    // The post list is the critical payload. P-09: request only the fields
    // the dashboard renders (title/excerpt/date/categories…). Full `content`
    // is NOT needed here — the editor reloads it via getPost(id) on open, and
    // crash recovery / offline copies already fetch full posts on demand.
    try {
      posts = await svc.getPosts(
        count: kPostPageSize,
        offset: 0,
        fields: const [
          'id',
          'title',
          'status',
          'date_gmt',
          'excerpt',
          'link',
          'slug',
          'categories',
          'tags',
          'author',
          'comment_status',
          'ping_status',
        ],
      );
    } catch (e) {
      // Classified + logged; the raw protocol error never reaches the UI.
      error = userFacingError(e, context: 'refresh.getPosts');
    }

    categories = await catsFuture;
    tags = await tagsFuture;
    authors = await authorsFuture;
    theme = await themeFuture;
    // A full first page implies there may be more posts to load.
    canLoadMore = posts.length >= kPostPageSize;

    loading = false;
    notifyListeners();
  }

  /// Concurrent theme probe: detects the blog theme at most once per account
  /// connection and persists it, but never blocks or fails the dashboard.
  Future<BlogTheme?> _probeTheme(BlogAccount account, BlogService svc) async {
    if (_themeProbedFor != account.id &&
        (theme == null || theme!.name == null || theme!.name == 'Default')) {
      _themeProbedFor = account.id;
      try {
        final detected = await svc.detectTheme();
        await store.saveTheme(account.id, detected);
        await store.updateAccount(account.copyWith(themeName: detected.name));
        return detected;
      } catch (e) {
        debugPrint('theme detection failed (non-fatal): $e');
      }
    }
    return theme;
  }

  /// Loads the next page of posts for the dashboard (P1-5 infinite scroll).
  ///
  /// Runs independently of [refresh] so scrolling never blocks on a full
  /// reload. New posts are appended (deduped by id) and the offset advances;
  /// when a fetch returns fewer than a full page, [canLoadMore] flips to
  /// false so the list stops offering more.
  Future<void> loadMorePosts() async {
    final svc = _service;
    final account = currentAccount;
    if (svc == null || account == null) return;
    if (loading || loadingMore || !canLoadMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final more = await svc.getPosts(
        count: kPostPageSize,
        offset: _postOffset + kPostPageSize,
        fields: const [
          'id',
          'title',
          'status',
          'date_gmt',
          'excerpt',
          'link',
          'slug',
          'categories',
          'tags',
          'author',
          'comment_status',
          'ping_status',
        ],
      );
      if (more.isEmpty) {
        canLoadMore = false;
      } else {
        final seen = <String>{for (final p in posts) p.id ?? ''};
        final appended = more
            .where((p) => (p.id ?? '').isEmpty || !seen.contains(p.id ?? ''))
            .toList();
        posts = [...posts, ...appended];
        _postOffset += kPostPageSize;
        canLoadMore = more.length >= kPostPageSize;
      }
    } catch (e) {
      // Don't blank the list or disable further loads on a transient error;
      // just log and let the user scroll/retry.
      debugPrint('loadMorePosts failed: $e');
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  /// Resolves category ids to display names (O(1) via a lazily rebuilt
  /// id→name map — the dashboard list used to do an O(n) linear scan per
  /// category per tile, i.e. O(n·m) across the whole list on every frame).
  Map<String, String>? _categoryNameCache;
  List<PostCategory>? _categoryNameSource;

  Map<String, String>? _tagNameCache;
  List<PostTag>? _tagNameSource;

  String categoryName(String id) {
    if (!identical(categories, _categoryNameSource)) {
      _categoryNameSource = categories;
      _categoryNameCache = {for (final c in categories) c.id: c.name};
    }
    return _categoryNameCache![id] ?? id;
  }

  // --- Local drafts ---------------------------------------------------------

  Future<void> _loadLocalDrafts() async {
    final id = currentAccount?.id;
    if (id == null) return;
    localDrafts = await drafts.loadDrafts(id);
  }

  /// Saves (or updates) a local draft for the current account and refreshes
  /// the home list.
  Future<void> saveLocalDraft(LocalDraft draft) async {
    try {
      await drafts.saveDraft(draft);
    } catch (e) {
      // saveDraft deliberately refuses to overwrite a corrupt payload
      // (data-loss guard); surface it instead of failing silently.
      debugPrint('saveLocalDraft failed: $e');
      error = 'Could not save the local draft.';
      notifyListeners();
      return;
    }
    await _loadLocalDrafts();
    notifyListeners();
  }

  /// Deletes a local draft for the current account.
  Future<void> deleteLocalDraft(String draftId) async {
    final id = currentAccount?.id;
    if (id == null) return;
    try {
      await drafts.deleteDraft(id, draftId);
    } catch (e) {
      debugPrint('deleteLocalDraft failed: $e');
      error = 'Could not delete the local draft.';
      notifyListeners();
      return;
    }
    await _loadLocalDrafts();
    notifyListeners();
  }

  /// Publishes a parked local (offline-written) draft to the blog with
  /// newPost and removes it from the local list on success — the home
  /// screen's "publish to blog" action for non-offline-copy drafts.
  ///
  /// [publish] controls whether the post is published or only saved as a
  /// draft on the server; previously this was derived from the draft's
  /// status (always `draft` for a local draft), so the user's intent to
  /// *publish* was silently downgraded to a draft upload.
  Future<bool> publishLocalDraft(LocalDraft draft, {bool publish = false}) async {
    final svc = _service;
    final account = currentAccount;
    if (svc == null || account == null) return false;
    final post = draft.toBlogPost();
    final id = await svc.newPost(post, publish: publish);
    if (id.isEmpty) return false;
    await deleteLocalDraft(draft.id);
    unawaited(refresh());
    return true;
  }

  // --- Offline copies of server posts ---------------------------------------

  /// The local offline copy of a server post, if one exists.
  LocalDraft? offlineCopyOf(String? postId) => postId == null
      ? null
      : localDrafts.where((d) => d.postId == postId).firstOrNull;

  /// Downloads the full post and stores/refreshes it as an offline copy
  /// (editable while offline, pushable back with editPost). Also warms
  /// the image cache so the copy opens with working images offline.
  Future<bool> saveOfflinePost(BlogPost post) async {
    final account = currentAccount;
    if (account == null || post.id == null) return false;
    final existing = offlineCopyOf(post.id);
    try {
      await drafts.saveDraft(LocalDraft(
        id: existing?.id ?? newDraftId(),
        accountId: account.id,
        title: post.title,
        content: post.content,
        excerpt: post.excerpt,
        slug: post.slug,
        updatedAt: DateTime.now(),
        postId: post.id,
        postStatus: post.status.wpValue,
        isPage: post.isPage,
        categories: List.of(post.categories),
        tags: List.of(post.tags),
        // P3-13: baseline the conflict check against the server's own
        // modified_gmt (not the local download time), so the comparison is
        // server-clock vs server-clock and immune to device-clock skew.
        remoteModified: post.modified ?? DateTime.now(),
      ));
    } catch (e) {
      debugPrint('saveOfflinePost failed: $e');
      error = 'Could not save the offline copy.';
      notifyListeners();
      return false;
    }
    await _loadLocalDrafts();
    notifyListeners();
    unawaited(MediaCache.instance.prefetchImages(post.content));
    return true;
  }

  /// Pushes an edited offline copy back to the server.
  ///
  /// Refuses to overwrite when the post changed on the blog after the offline
  /// copy was taken: pushing blindly (last-write-wins) silently discarded
  /// edits made elsewhere.
  ///
  /// The check is best effort — if the remote copy cannot be read the push
  /// proceeds rather than being blocked by a transient failure.
  Future<bool> syncOfflineCopy(LocalDraft draft) async {
    final svc = _service;
    final account = currentAccount;
    if (svc == null || account == null || !draft.isOfflineCopy) return false;
    final post = draft.toBlogPost();
    final id = post.id;
    final baseline = draft.remoteModified;
    if (id == null) return false;

    if (baseline != null) {
      try {
        final remote = await svc.getPost(id, isPage: draft.isPage);
        final remoteModified = remote.modified;
        if (remoteModified != null &&
            remoteModified.isAfter(baseline.add(kConflictClockSkew))) {
          error = 'This post changed on the blog since your offline copy was '
              'saved. Sync is paused to avoid overwriting those changes.';
          notifyListeners();
          return false;
        }
      } catch (e) {
        debugPrint('syncOfflineCopy: conflict check skipped: $e');
      }
    }

    final ok = await svc.editPost(post,
        publish: post.status != PostStatus.draft);
    if (!ok) return false;
    await saveOfflinePost(post);
    return true;
  }

  /// Generates an id from the current time plus a random suffix.
  ///
  /// The two generators used to be separate near-duplicates, and the account
  /// one concatenated the parts with no separator at all.
  String _generateId(String prefix) =>
      '$prefix-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  String newDraftId() => _generateId('local');

  /// Creates a category on the blog and refreshes the local taxonomy list.
  /// Both protocol stacks implement this (wp.newCategory / REST terms).
  Future<bool> createCategory(String name) async {
    final svc = _service;
    if (svc == null || name.trim().isEmpty) return false;
    try {
      final id = await svc.newCategory(name.trim());
      final created = await svc.getCategories();
      categories = created;
      // Pre-select the new category in the editor flow by leaving selection
      // to the caller — here we only refresh the taxonomy.
      notifyListeners();
      return id.isNotEmpty;
    } catch (e) {
      error = userFacingError(e, context: 'createCategory');
      notifyListeners();
      return false;
    }
  }

  /// Resolves tag ids to display names (O(1) via a lazily rebuilt id→name
  /// map, matching [categoryName] — the previous linear scan per call was
  /// O(n) across every tagged tile on every frame).
  String tagName(String idOrName) {
    if (!identical(tags, _tagNameSource)) {
      _tagNameSource = tags;
      _tagNameCache = {for (final t in tags) t.id: t.name};
    }
    return _tagNameCache![idOrName] ?? idOrName;
  }

  /// All known tag names, used for autocomplete in the editor.
  List<String> get tagNames => tags.map((t) => t.name).toList();

  String newAccountId() => _generateId('acct');

  /// Persists and applies a new app-wide color scheme preference (P3-15).
  /// Notifies so [AppShell] can rebuild [MaterialApp] with the new mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode == mode) return;
    themeMode = mode;
    try {
      (await store.prefs).setString('olw.themeMode', _themeModeToString(mode));
    } catch (e) {
      debugPrint('AppState.setThemeMode failed: $e');
    }
    notifyListeners();
  }

  static ThemeMode _themeModeFromString(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _themeModeToString(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
