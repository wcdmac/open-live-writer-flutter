import 'dart:convert';

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

  static LocalDraft fromJson(Map<String, dynamic> json) => LocalDraft(
        id: json['id'] as String,
        accountId: json['accountId'] as String,
        title: (json['title'] ?? '') as String,
        content: (json['content'] ?? '') as String,
        excerpt: (json['excerpt'] ?? '') as String,
        slug: json['slug'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        postId: json['postId'] as String?,
        postStatus: json['postStatus'] as String?,
        isPage: (json['isPage'] ?? false) as bool,
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

  // --- Drafts --------------------------------------------------------------

  Future<List<LocalDraft>> loadDrafts(String accountId) async {
    final raw = (await _prefs).getString('$_draftsPrefix$accountId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => LocalDraft.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDraft(LocalDraft draft) async {
    final drafts = await loadDrafts(draft.accountId);
    final idx = drafts.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      drafts[idx] = draft;
    } else {
      drafts.insert(0, draft);
    }
    await (await _prefs).setString('$_draftsPrefix${draft.accountId}',
        jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  Future<void> deleteDraft(String accountId, String draftId) async {
    final drafts = await loadDrafts(accountId);
    drafts.removeWhere((d) => d.id == draftId);
    await (await _prefs).setString('$_draftsPrefix$accountId',
        jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

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
