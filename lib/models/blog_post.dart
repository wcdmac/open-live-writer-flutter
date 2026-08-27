/// Publish state of a post, mirroring OpenLiveWriter.Extensibility.BlogPost.
enum PostStatus {
  draft,
  pending,
  private,
  publish,
  scheduled,
  trash;

  String get label => switch (this) {
        PostStatus.draft => 'Draft',
        PostStatus.pending => 'Pending review',
        PostStatus.private => 'Private',
        PostStatus.publish => 'Published',
        PostStatus.scheduled => 'Scheduled',
        PostStatus.trash => 'Trash',
      };

  /// WordPress XML-RPC post status value.
  String get wpValue => switch (this) {
        PostStatus.draft => 'draft',
        PostStatus.pending => 'pending',
        PostStatus.private => 'private',
        PostStatus.publish => 'publish',
        PostStatus.scheduled => 'future',
        PostStatus.trash => 'trash',
      };

  /// Unknown values (auto-draft, inherit, new statuses…) map to draft:
  /// defaulting to publish would let a status round-trip accidentally
  /// publish content that was never meant to be public.
  static PostStatus fromWp(String? value) => switch (value) {
        'draft' => PostStatus.draft,
        'pending' => PostStatus.pending,
        'private' => PostStatus.private,
        'future' || 'scheduled' => PostStatus.scheduled,
        'publish' => PostStatus.publish,
        'trash' => PostStatus.trash,
        _ => PostStatus.draft,
      };
}

/// A blog category (optionally hierarchical, like the original
/// BlogPostCategory with parent support).
class PostCategory {
  const PostCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.description,
    this.slug,
  });

  final String id;
  final String name;
  final String? parentId;
  final String? description;
  final String? slug;

  PostCategory copyWith({String? parentId}) => PostCategory(
        id: id,
        name: name,
        parentId: parentId ?? this.parentId,
        description: description,
        slug: slug,
      );
}

/// A tag / keyword (BlogPostKeyword in the original codebase).
class PostTag {
  const PostTag({required this.id, required this.name, this.slug});

  final String id;
  final String name;
  final String? slug;
}

/// Result of a media upload (newMediaObject / wp.uploadFile).
class MediaUploadResult {
  const MediaUploadResult({
    required this.id,
    required this.url,
    this.file,
    this.type,
    this.thumbnailUrl,
  });

  final String id;
  final String url;
  final String? file;
  final String? type;
  final String? thumbnailUrl;

  /// HTML snippet inserted into the post content.
  String get html => '<img src="$url" alt="${file ?? ''}" />';
}

/// The core post data model, ported from
/// OpenLiveWriter.Extensibility.BlogPost (BlogPost.cs).
class BlogPost {
  BlogPost({
    this.id,
    this.title = '',
    this.content = '',
    this.excerpt = '',
    this.slug,
    this.password,
    this.authorId,
    this.authorName,
    this.permalink,
    this.status = PostStatus.draft,
    this.isPage = false,
    this.pageParentId,
    this.pageOrder,
    this.dateCreated,
    this.datePublished,
    this.commentsEnabled = true,
    this.pingsEnabled = true,
    List<String>? categories,
    List<String>? tags,
  })  : categories = categories ?? [],
        tags = tags ?? [];

  String? id;
  String title;
  String content;

  /// Short summary shown in archives / search results.
  String excerpt;

  /// URL slug (post_name).
  String? slug;

  /// Post password protection (wp_password).
  String? password;

  String? authorId;
  String? authorName;
  String? permalink;

  PostStatus status;
  bool isPage;
  String? pageParentId;
  int? pageOrder;
  DateTime? dateCreated;
  DateTime? datePublished;
  bool commentsEnabled;
  bool pingsEnabled;
  List<String> categories;
  List<String> tags;

  bool get isNew => id == null || id!.isEmpty;
  bool get isPublished => status == PostStatus.publish ||
      status == PostStatus.scheduled ||
      status == PostStatus.private;

  /// Cached result for [displayExcerpt]: the list view calls it on every
  /// tile build, and running two regexes over full post content per frame
  /// janks scrolling on long posts.
  String? _excerptCache;
  String? _excerptCacheSrc;

  /// Excerpt with a sane fallback (first 160 chars of plain text content).
  String get displayExcerpt {
    if (excerpt.trim().isNotEmpty) return excerpt;
    if (_excerptCache != null && _excerptCacheSrc == content) {
      return _excerptCache!;
    }
    final plain = content
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final result =
        plain.length > 160 ? '${plain.substring(0, 160)}…' : plain;
    _excerptCacheSrc = content;
    _excerptCache = result;
    return result;
  }

  BlogPost copy() => BlogPost(
        id: id,
        title: title,
        content: content,
        excerpt: excerpt,
        slug: slug,
        password: password,
        authorId: authorId,
        authorName: authorName,
        permalink: permalink,
        status: status,
        isPage: isPage,
        pageParentId: pageParentId,
        pageOrder: pageOrder,
        dateCreated: dateCreated,
        datePublished: datePublished,
        commentsEnabled: commentsEnabled,
        pingsEnabled: pingsEnabled,
        categories: List.of(categories),
        tags: List.of(tags),
      );
}
