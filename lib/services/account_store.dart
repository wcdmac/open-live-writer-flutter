import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/blog.dart';
import 'theme_detector.dart';

/// Persists blog accounts (non-secret metadata in SharedPreferences,
/// passwords in OS secure storage / keychain).
class AccountStore {
  AccountStore({
    SharedPreferences? prefs,
    FlutterSecureStorage? secureStorage,
  })  : _prefs = prefs,
        _secure = secureStorage ?? const FlutterSecureStorage();

  SharedPreferences? _prefs;
  final FlutterSecureStorage _secure;
  static const _accountsKey = 'olw.accounts';

  Future<SharedPreferences> get prefs async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Strict decode of the stored payload.
  ///
  /// Returns `null` when nothing is stored yet; throws when a payload exists
  /// but cannot be decoded. Mutation paths ([addAccount], [updateAccount],
  /// [removeAccount]) rewrite the whole key, so they must abort on a throw:
  /// treating an undecodable payload as "empty" would replace every saved
  /// account with the single one being written.
  Future<List<BlogAccount>?> _readAccounts() async {
    final p = await prefs;
    final raw = p.getString(_accountsKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('accounts payload is not a JSON list');
    }
    final out = <BlogAccount>[];
    for (final entry in decoded) {
      // Entry-level tolerance: skip the unusable record, keep the rest.
      if (entry is! Map) continue;
      final account = BlogAccount.fromJson(Map<String, dynamic>.from(entry));
      if (account.id.isEmpty) continue;
      out.add(account);
    }
    return out;
  }

  /// All saved accounts.
  Future<List<BlogAccount>> loadAccounts() async {
    try {
      return await _readAccounts() ?? const <BlogAccount>[];
    } catch (e) {
      // Read path: degrade to empty for display; the payload on disk is left
      // untouched because nothing rewrites it here.
      debugPrint('AccountStore: corrupt accounts payload: $e');
      return const <BlogAccount>[];
    }
  }

  Future<void> saveAccounts(List<BlogAccount> accounts) async {
    final p = await prefs;
    await p.setString(
        _accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  /// Stores / updates the password for an account (keychain).
  Future<void> savePassword(String accountId, String password) async {
    await _secure.write(key: 'olw.pass.$accountId', value: password);
  }

  Future<String?> loadPassword(String accountId) async {
    return _secure.read(key: 'olw.pass.$accountId');
  }

  Future<void> deletePassword(String accountId) async {
    await _secure.delete(key: 'olw.pass.$accountId');
  }

  Future<void> addAccount(BlogAccount account, String password) async {
    // Strict read: never rewrite over an undecodable payload.
    final accounts = await _readAccounts() ?? <BlogAccount>[];
    // Upsert by id — appending blindly would create duplicate rows for an
    // id that is already stored (and duplicate entries in secure storage).
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      accounts[idx] = account;
    } else {
      accounts.add(account);
    }
    await saveAccounts(accounts);
    await savePassword(account.id, password);
  }

  Future<void> updateAccount(BlogAccount account) async {
    final accounts = await _readAccounts() ?? <BlogAccount>[];
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      accounts[idx] = account;
      await saveAccounts(accounts);
    }
  }

  Future<void> removeAccount(String accountId) async {
    final accounts = await _readAccounts() ?? <BlogAccount>[];
    accounts.removeWhere((a) => a.id == accountId);
    await saveAccounts(accounts);
    await deletePassword(accountId);
  }

  /// Caches a detected blog theme per account (avoids refetching).
  Future<void> saveTheme(String accountId, BlogTheme theme) async {
    final p = await prefs;
    await p.setString('olw.theme.$accountId', jsonEncode({
      'name': theme.name,
      'fontFamily': theme.fontFamily,
      'bodyColor': theme.bodyColor,
      'headingColor': theme.headingColor,
      'linkColor': theme.linkColor,
      'backgroundColor': theme.backgroundColor,
      'contentWidth': theme.contentWidth,
    }));
  }

  Future<BlogTheme?> loadTheme(String accountId) async {
    final p = await prefs;
    final raw = p.getString('olw.theme.$accountId');
    if (raw == null) return null;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw));
      return BlogTheme(
        name: m['name'],
        fontFamily: m['fontFamily'],
        bodyColor: m['bodyColor'] ?? 'rgba(0, 0, 0, 0.87)',
        headingColor: m['headingColor'] ?? 'rgba(0, 0, 0, 0.89)',
        linkColor: m['linkColor'] ?? '#2563eb',
        backgroundColor: m['backgroundColor'] ?? '#ffffff',
        contentWidth: (m['contentWidth'] as num?)?.toDouble() ?? 720,
      );
    } catch (_) {
      return null;
    }
  }
}
