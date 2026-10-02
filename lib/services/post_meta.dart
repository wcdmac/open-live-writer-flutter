import '../models/blog_post.dart';

/// SEO / social-sharing metadata carried as custom fields.
///
/// Open Live Writer emits the well-known Yoast SEO keys so the values land in
/// the most popular WordPress SEO plugin without extra configuration. Sites
/// without the plugin simply ignore the unknown meta (WordPress REST returns
/// `meta` verbatim; XML-RPC carries them as `post_meta` custom fields).
class PostMetaKeys {
  /// REST `meta` key (and XML-RPC `post_meta` `key`) for the SEO title.
  static const seoTitle = '_yoast_wpseo_title';

  /// REST `meta` key for the SEO meta description.
  static const seoDescription = '_yoast_wpseo_metadesc';

  /// REST `meta` key for the Open Graph image URL.
  static const ogImage = '_yoast_wpseo_opengraph-image';
}

/// Builds the REST `meta` map for a post.
///
/// Only non-empty fields are included, so an untouched post ships no `meta`
/// at all (the server keeps its existing SEO values instead of overwriting
/// them with blanks). Whitespace-only values are treated as empty.
Map<String, dynamic> buildPostMeta(BlogPost post) {
  final meta = <String, dynamic>{};
  final title = post.seoTitle?.trim() ?? '';
  final desc = post.seoDescription?.trim() ?? '';
  final og = post.ogImageUrl?.trim() ?? '';
  if (title.isNotEmpty) meta[PostMetaKeys.seoTitle] = title;
  if (desc.isNotEmpty) meta[PostMetaKeys.seoDescription] = desc;
  if (og.isNotEmpty) meta[PostMetaKeys.ogImage] = og;
  return meta;
}

/// Builds the XML-RPC `post_meta` list for a post.
///
/// XML-RPC expresses custom fields as a list of `{key, value}` structs
/// (some servers also include an `id`), so the same data is re-shaped into
/// that form. Returns an empty list when there is nothing to send.
List<Map<String, String>> buildXmlRpcPostMeta(BlogPost post) {
  return buildPostMeta(post)
      .entries
      .map((e) => {'key': e.key, 'value': '${e.value}'})
      .toList();
}

/// Reads a single Yoast key out of a REST `meta` map. Returns null when the
/// key is absent or not a string.
String? readRestMeta(dynamic meta, String key) {
  if (meta is Map && meta[key] != null) return '${meta[key]}';
  return null;
}

/// Reads a single Yoast key out of an XML-RPC `post_meta` list (each element
/// a `{key, value}` / `{id, key, value}` struct). Returns null when absent.
String? readXmlRpcMeta(dynamic postMeta, String key) {
  if (postMeta is List) {
    for (final item in postMeta) {
      if (item is Map && '${item['key']}' == key) {
        return '${item['value']}';
      }
    }
  }
  return null;
}
