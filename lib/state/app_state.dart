import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/blog.dart';
import '../models/blog_post.dart';
import '../services/account_store.dart';
import '../services/blog_service.dart';
import '../services/theme_detector.dart';

/// Root application state: accounts, the active account, its taxonomies
/// and post list. Backed by [AccountStore] for persistence.
class AppState extends ChangeNotifier {
  AppState({AccountStore? store}) : store = store ?? AccountStore();

  final AccountStore store;

  List<BlogAccount> accounts = [];
  BlogAccount? currentAccount;
  BlogService? _service;
  String? _currentPassword;

  List<PostCategory> categories = [];
  List<PostTag> tags = [];
  List<BlogPost> posts = [];
  BlogTheme? theme;
  bool loading = false;
  String? error;

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
    notifyListeners();
  }

  Future<void> _connectCurrent() async {
    final account = currentAccount;
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
    if (svc == null) return;
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
      // Detect theme once, then cache it.
      final account = currentAccount!;
      if (theme == null || theme!.name == null || theme!.name == 'Default') {
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
