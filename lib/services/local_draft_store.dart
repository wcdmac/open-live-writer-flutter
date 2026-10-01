import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/blog_post.dart';

/// A locally stored draft — written offline or auto-saved on network
/// failure, later opened and published to the blog. Stored per account.
///
/// When [postId] is set the entry is an OFFLINE COPY of an existing
/// server post (downloaded for offline editing); otherwise it is a plain
/// new-post draft.
class LocalDraft {
  LocalDraft({
    required this.id,
    required this.accountId,
    required this.title,
    required this.content,
    this.excerpt = '',
    this.slug,
    required this.updatedAt,
    this.postId,
    this.postStatus,
    this.isPage = false,
    List<String>? categories,
    List<String>? tags,
    this.remoteModified,
  })  : categories = categories ?? const [],
        tags = tags ?? const [];

  final String id;
  final String accountId;
  String title;
  String content;
  String excerpt;
  String? slug;
  DateTime updatedAt;

  /// Server post id when this draft is an offline copy of a post.
  final String? postId;

  /// WordPress status value ('publish', 'draft', ...) of the source post.
  final String? postStatus;
  final bool isPage;

  /// Category ids / tag names of the source post.
  final List<String> categories;
  final List<String> tags;

  /// When the server copy was last known to match this content.
  final DateTime? remoteModified;

  bool get isOfflineCopy => postId != null && postId!.isNotEmpty;

  /// Rebuilds the server post model from this copy, so the editor and
  /// sync flows can push it back with editPost.
  BlogPost toBlogPost() => BlogPost(
        id: postId,
        title: title,
        content: content,
        excerpt: excerpt,
        slug: slug,
        status: PostStatus.fromWp(postStatus),
        isPage: isPage,
        categories: List.of(categories),
        tags: List.of(tags),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'title': title,
        'content': content,
        'excerpt': excerpt,
        'slug': slug,
        'updatedAt': updatedAt.toIso8601String(),
        'postId': postId,
        'postStatus': postStatus,
        'isPage': isPage,
        'categories': categories,
        'tags': tags,
        'remoteModified': remoteModified?.toIso8601String(),
      };

  /// Tolerant decode: every field falls back to a usable default instead of
  /// throwing. A single legacy/malformed field used to abort decoding of the
  /// whole list, which the caller then treated as "no drafts stored" and
  /// overwrote — silently destroying every other draft.
  static LocalDraft fromJson(Map<String, dynamic> json) => LocalDraft(
        id: (json['id'] ?? '') as String,
        accountId: (json['accountId'] ?? '') as String,
        title: (json['title'] ?? '') as String,
        content: (json['content'] ?? '') as String,
        excerpt: (json['excerpt'] ?? '') as String,
        slug: json['slug'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        postId: json['postId'] as String?,
        postStatus: json['postStatus'] as String?,
        isPage: (json['isPage'] ?? false) == true,
        categories: ((json['categories'] ?? const []) as List<dynamic>)
            .map((e) => '$e')
            .toList(),
        tags: ((json['tags'] ?? const []) as List<dynamic>)
            .map((e) => '$e')
            .toList(),
        remoteModified:
            DateTime.tryParse(json['remoteModified'] as String? ?? ''),
      );
}

/// Crash-recovery snapshot: one slot per account, refreshed while a NEW
/// post is being written. Restored on the next editor open; cleared once
/// the post is saved to the blog or explicitly discarded.
class CrashSnapshot {
  CrashSnapshot({required this.title, required this.content, required this.savedAt});

  final String title;
  final String content;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'savedAt': savedAt.toIso8601String(),
      };

  static CrashSnapshot? fromJson(Map<String, dynamic> json) {
    final content = (json['content'] ?? '') as String;
    if (content.trim().isEmpty && (json['title'] ?? '').toString().trim().isEmpty) {
      return null;
    }
    return CrashSnapshot(
      title: (json['title'] ?? '') as String,
      content: content,
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// SharedPreferences-backed persistence for local drafts and the crash
/// snapshot. Deliberately dependency-free (no sqflite): drafts are text
/// payloads, and prefs keeps the desktop builds trivial.
class LocalDraftStore {
  static const _draftsPrefix = 'olw.drafts.';
  static const _crashPrefix = 'olw.crash.';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Serializes draft mutations: saveDraft/deleteDraft are read-modify-write
  /// over the same SharedPreferences key, and two interleaved calls (e.g.
  /// auto-parking a draft while the user deletes another) silently lose
  /// one change. Every mutation chains onto the previous one.
  Future<void> _mutationLock = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _mutationLock.then((_) => action());
    // Keep the chain alive regardless of the action's outcome.
    _mutationLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  // --- Drafts --------------------------------------------------------------

  /// Strict decode of the stored payload.
  ///
  /// Returns `null` when nothing is stored yet (absent/empty key) and throws
  /// when a payload exists but cannot be decoded.
  ///
  /// The distinction matters: `saveDraft`/`deleteDraft` rewrite the whole
  /// key. Treating an undecodable payload as "empty" would replace every
  /// draft with the single one being saved, so mutation paths MUST use this
  /// and abort on a throw rather than fall back to an empty list.
  Future<List<LocalDraft>?> _readDrafts(String accountId) async {
    final raw = (await _prefs).getString('$_draftsPrefix$accountId');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('drafts payload is not a JSON list');
    }
    final out = <LocalDraft>[];
    for (final entry in decoded) {
      // Entry-level tolerance: skip the unusable record, keep the rest.
      if (entry is! Map) continue;
      final draft = LocalDraft.fromJson(Map<String, dynamic>.from(entry));
      if (draft.id.isEmpty) continue;
      out.add(draft);
    }
    return out;
  }

  Future<List<LocalDraft>> loadDrafts(String accountId) async {
    try {
      return await _readDrafts(accountId) ?? const <LocalDraft>[];
    } catch (e) {
      // Read path: degrade to empty for display, but never silently — the
      // payload stays on disk untouched because nothing rewrites it here.
      debugPrint('LocalDraftStore: corrupt drafts for $accountId: $e');
      return const <LocalDraft>[];
    }
  }

  Future<void> saveDraft(LocalDraft draft) => _synchronized(() async {
        // Strict: a corrupt payload aborts the write instead of being
        // overwritten (see [_readDrafts]).
        final drafts = await _readDrafts(draft.accountId) ?? <LocalDraft>[];
        final idx = drafts.indexWhere((d) => d.id == draft.id);
        if (idx >= 0) {
          drafts[idx] = draft;
        } else {
          drafts.insert(0, draft);
        }
        await (await _prefs).setString('$_draftsPrefix${draft.accountId}',
            jsonEncode(drafts.map((d) => d.toJson()).toList()));
      });

  Future<void> deleteDraft(String accountId, String draftId) =>
      _synchronized(() async {
        final drafts = await _readDrafts(accountId) ?? <LocalDraft>[];
        drafts.removeWhere((d) => d.id == draftId);
        await (await _prefs).setString('$_draftsPrefix$accountId',
            jsonEncode(drafts.map((d) => d.toJson()).toList()));
      });

  // --- Crash snapshot --------------------------------------------------------

  Future<CrashSnapshot?> loadSnapshot(String accountId) async {
    final raw = (await _prefs).getString('$_crashPrefix$accountId');
    if (raw == null) return null;
    try {
      return CrashSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSnapshot(String accountId, CrashSnapshot snapshot) async {
    await (await _prefs)
        .setString('$_crashPrefix$accountId', jsonEncode(snapshot.toJson()));
  }

  Future<void> clearSnapshot(String accountId) async {
    await (await _prefs).remove('$_crashPrefix$accountId');
  }
}
