import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/blog.dart';
import '../models/blog_post.dart';
import '../services/account_store.dart';
import '../services/blog_service.dart';
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

  Future<void> load() async {
    accounts = await store.loadAccounts();
    if (accounts.isNotEmpty) {
      final savedCurrentId = (await store.prefs).getString('olw.currentAccount');
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
      notifyListeners();
      if (currentAccount != null) await refresh();
    }
    notifyListeners();
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
    loading = true;
    error = null;
    notifyListeners();

    // Taxonomies are best-effort; failures degrade silently.
    final catsFuture = svc.getCategories().catchError((Object e) {
      if (kDebugMode) print('getCategories failed: $e');
      return <PostCategory>[];
    });
    final tagsFuture = svc.getTags().catchError((Object e) {
      if (kDebugMode) print('getTags failed: $e');
      return <PostTag>[];
    });

    // The post list is the critical payload.
    try {
      posts = await svc.getPosts(count: 50);
    } catch (e) {
      error = 'Sync failed: $e';
      if (kDebugMode) print('AppState.refresh getPosts error: $e');
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
      if (kDebugMode) print('theme detection failed (non-fatal): $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Resolves category ids to display names.
  String categoryName(String id) {
    final c = categories.where((c) => c.id == id).firstOrNull;
    return c?.name ?? id;
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
    await drafts.saveDraft(draft);
    await _loadLocalDrafts();
    notifyListeners();
  }

  /// Deletes a local draft for the current account.
  Future<void> deleteLocalDraft(String draftId) async {
    final id = currentAccount?.id;
    if (id == null) return;
    await drafts.deleteDraft(id, draftId);
    await _loadLocalDrafts();
    notifyListeners();
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
    await _loadLocalDrafts();
    notifyListeners();
    unawaited(MediaCache.instance.prefetchImages(post.content));
    return true;
  }

  /// Pushes an edited offline copy back to the server (last-write-wins).
  /// On success the copy is refreshed so it stays in sync.
  Future<bool> syncOfflineCopy(LocalDraft draft) async {
    final svc = _service;
    final account = currentAccount;
    if (svc == null || account == null || !draft.isOfflineCopy) return false;
    final post = draft.toBlogPost();
    final ok = await svc.editPost(post,
        publish: post.status != PostStatus.draft);
    if (!ok) return false;
    await saveOfflinePost(post);
    return true;
  }

  String newDraftId() =>
      'local-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

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
      if (kDebugMode) print('createCategory failed: $e');
      error = 'Create category failed: $e';
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

  String newAccountId() {
    final rand = Random();
    return DateTime.now().millisecondsSinceEpoch.toString() +
        rand.nextInt(9999).toString();
  }
}
