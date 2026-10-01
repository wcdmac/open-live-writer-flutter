import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/blog.dart';
import '../models/blog_post.dart';
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
  List<BlogPost> posts = [];
  List<LocalDraft> localDrafts = [];
  BlogTheme? theme;
  bool loading = false;
  String? error;

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
        final savedCurrentId =
            (await store.prefs).getString('olw.currentAccount');
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

    // The post list is the critical payload. P-09: request only the fields
    // the dashboard renders (title/excerpt/date/categories…). Full `content`
    // is NOT needed here — the editor reloads it via getPost(id) on open, and
    // crash recovery / offline copies already fetch full posts on demand.
    try {
      posts = await svc.getPosts(
        count: 50,
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

    try {
      // Probe the theme at most once per account connection; a failed
      // probe returning "Default" must not re-fetch the homepage on
      // every subsequent refresh.
      if (_themeProbedFor != account.id &&
          (theme == null || theme!.name == null || theme!.name == 'Default')) {
        _themeProbedFor = account.id;
        theme = await svc.detectTheme();
        await store.saveTheme(account.id, theme!);
        await store.updateAccount(
            account.copyWith(themeName: theme!.name));
      }
    } catch (e) {
      debugPrint('theme detection failed (non-fatal): $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Resolves category ids to display names (O(1) via a lazily rebuilt
  /// id→name map — the dashboard list used to do an O(n) linear scan per
  /// category per tile, i.e. O(n·m) across the whole list on every frame).
  Map<String, String>? _categoryNameCache;
  List<PostCategory>? _categoryNameSource;

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
        remoteModified: DateTime.now(),
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
            remoteModified.isAfter(baseline.add(const Duration(seconds: 1)))) {
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

  /// Resolves tag ids to display names.
  String tagName(String idOrName) {
    final t = tags.where((t) => t.id == idOrName).firstOrNull;
    return t?.name ?? idOrName;
  }

  /// All known tag names, used for autocomplete in the editor.
  List<String> get tagNames => tags.map((t) => t.name).toList();

  String newAccountId() => _generateId('acct');
}
