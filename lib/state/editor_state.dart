import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/blog_post.dart';
import '../services/blog_service.dart';
import '../services/theme_detector.dart';

/// State for the post editor. Holds the post being edited and exposes
/// a change stream that the live preview subscribes to — this is what
/// powers the real-time preview updates.
class EditorState extends ChangeNotifier {
  EditorState({this.service, BlogPost? initialPost, this.theme})
      : post = initialPost ?? BlogPost();

  final BlogService? service;
  BlogTheme? theme;

  BlogPost post;

  /// Debounced notifier used by the preview pane.
  final _contentChanged = StreamController<String>.broadcast();
  Stream<String> get contentChanged => _contentChanged.stream;

  Timer? _debounce;
  bool saving = false;
  String? saveError;
  String? lastSavedId;

  bool get isDirty => _dirty;
  bool _dirty = false;

  void updateContent(String content) {
    if (post.content == content) return;
    post.content = content;
    _dirty = true;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _contentChanged.add(content);
    });
  }

  void updateTitle(String title) {
    post.title = title;
    _dirty = true;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _contentChanged.add(post.content);
    });
  }

  void updateExcerpt(String excerpt) {
    post.excerpt = excerpt;
    _dirty = true;
    notifyListeners();
  }

  void updateSlug(String slug) {
    post.slug = slug;
    _dirty = true;
    notifyListeners();
  }

  void updateStatus(PostStatus status) {
    post.status = status;
    _dirty = true;
    notifyListeners();
  }

  void toggleCategory(String categoryId) {
    if (post.categories.contains(categoryId)) {
      post.categories.remove(categoryId);
    } else {
      post.categories.add(categoryId);
    }
    _dirty = true;
    notifyListeners();
  }

  void setTags(List<String> tags) {
    post.tags = tags;
    _dirty = true;
    notifyListeners();
  }

  void setPublishDate(DateTime? date) {
    post.datePublished = date;
    if (date != null && date.isAfter(DateTime.now())) {
      post.status = PostStatus.scheduled;
    }
    _dirty = true;
    notifyListeners();
  }

  void setIsPage(bool isPage) {
    post.isPage = isPage;
    _dirty = true;
    notifyListeners();
  }

  void setCommentsEnabled(bool enabled) {
    post.commentsEnabled = enabled;
    _dirty = true;
    notifyListeners();
  }

  void setPingsEnabled(bool enabled) {
    post.pingsEnabled = enabled;
    _dirty = true;
    notifyListeners();
  }

  /// Saves the post (draft when [publish] is false).
  Future<bool> save({required bool publish}) async {
    final svc = service;
    if (svc == null) {
      saveError = 'No blog connection.';
      notifyListeners();
      return false;
    }
    saving = true;
    saveError = null;
    notifyListeners();
    try {
      if (post.isNew) {
        final id = await svc.newPost(post, publish: publish);
        post.id = id;
        lastSavedId = id;
      } else {
        await svc.editPost(post, publish: publish);
        lastSavedId = post.id;
      }
      if (publish && post.status == PostStatus.draft) {
        post.status = PostStatus.publish;
      }
      _dirty = false;
      return true;
    } catch (e) {
      saveError = 'Save failed: $e';
      if (kDebugMode) print('EditorState.save error: $e');
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _contentChanged.close();
    super.dispose();
  }
}
