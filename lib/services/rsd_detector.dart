import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/blog.dart';
import 'rest/wordpress_rest.dart';

/// Result of auto-detecting a blog's connection settings.
class BlogDetection {
  const BlogDetection({
    required this.homepageUrl,
    this.xmlrpcUrl,
    this.flavor,
    this.blogId,
    this.restRoot,
    this.engineName,
  });

  final String homepageUrl;

  /// XML-RPC endpoint (from RSD `apiLink` or wlwmanifest).
  final String? xmlrpcUrl;

  /// Best API flavor detected (WordPress preferred).
  final XmlRpcFlavor? flavor;

  /// Blog id hint from RSD.
  final String? blogId;

  /// WordPress REST API root when available.
  final String? restRoot;

  /// Engine name reported by RSD (e.g. "WordPress").
  final String? engineName;

  bool get isWordPress =>
      (engineName ?? '').toLowerCase().contains('wordpress') ||
      flavor == XmlRpcFlavor.wordpress ||
      restRoot != null;
}

/// Port of RsdServiceDetector + WlwManifestDetector from
/// OpenLiveWriter.BlogClient.Detection.
///
/// Flow: homepage HTML -> `<link rel="EditURI">` -> RSD XML ->
/// pick the best API (WordPress > MovableType > MetaWeblog > Blogger),
/// while also probing the REST API via the `Link` header.
class RsdDetector {
  RsdDetector({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  /// Runs full detection for a site URL.
  Future<BlogDetection> detect(String siteUrl) async {
    final homepage =
        siteUrl.endsWith('/') ? siteUrl : '$siteUrl/';

    // REST discovery is independent of RSD and works even when
    // XML-RPC is disabled.
    final restRoot = await WordPressRestClient.discoverRestRoot(homepage,
        client: _http);

    final rsd = await _detectFromHomepage(homepage);
    if (rsd == null) {
      // Fallback: assume a standard WordPress layout.
      final guessed = homepage.replaceAll(RegExp(r'/+$'), '');
      return BlogDetection(
        homepageUrl: homepage,
        xmlrpcUrl: '$guessed/xmlrpc.php',
        flavor: XmlRpcFlavor.wordpress,
        blogId: '1',
        restRoot: restRoot,
        engineName: 'WordPress (assumed)',
      );
    }

    return BlogDetection(
      homepageUrl: homepage,
      xmlrpcUrl: rsd.xmlrpcUrl,
      flavor: rsd.flavor,
      blogId: rsd.blogId,
      restRoot: restRoot,
      engineName: rsd.engineName,
    );
  }

  /// Fetches the homepage and follows `<link rel="EditURI">` to the RSD doc.
  Future<BlogDetection?> _detectFromHomepage(String homepageUrl) async {
    String html;
    try {
      final res =
          await _http.get(Uri.parse(homepageUrl)).timeout(_timeout);
      html = res.body;
    } catch (_) {
      return null;
    }

    final doc = html_parser.parse(html);
    final editUri = doc.head
            ?.querySelector('link[rel="EditURI"]')
            ?.attributes['href'] ??
        doc.querySelector('link[rel="EditURI"]')?.attributes['href'];

    if (editUri != null) {
      final rsdUrl = Uri.parse(homepageUrl).resolve(editUri).toString();
      final rsd = await _detectFromRsdUrl(rsdUrl);
      if (rsd != null) return rsd;
    }

    // Fallback: wlwmanifest.xml (used by WLW/OLW for manifest capabilities).
    final manifestUri = doc.head
            ?.querySelector('link[rel="wlwmanifest"]')
            ?.attributes['href'] ??
        doc.querySelector('link[rel="wlwmanifest"]')?.attributes['href'];
    if (manifestUri != null) {
      final guessed = homepageUrl.replaceAll(RegExp(r'/+$'), '');
      return BlogDetection(
        homepageUrl: homepageUrl,
        xmlrpcUrl: '$guessed/xmlrpc.php',
        flavor: XmlRpcFlavor.wordpress,
        blogId: '1',
        engineName: 'WordPress (wlwmanifest)',
      );
    }

    return null;
  }

  /// Fetches and parses the RSD XML (port of DetectFromRsdUrl +
  /// the RSD parsing in RsdServiceDetector).
  Future<BlogDetection?> _detectFromRsdUrl(String rsdUrl) async {
    String xml;
    try {
      final res = await _http.get(Uri.parse(rsdUrl)).timeout(_timeout);
      xml = res.body;
    } catch (_) {
      return null;
    }

    try {
      final doc = XmlDocument.parse(xml);
      final root = doc.rootElement;
      if (root.name.local != 'rsd') return null;

      final service = root.findElements('service').firstOrNull;
      final engineName =
          service?.findElements('engineName').firstOrNull?.innerText;

      // Collect all APIs; WordPress is preferred, matching the original
      // priority order in RsdServiceDetector.
      final apis = <({String name, bool preferred, String blogId, String link})>[];
      for (final api
          in service?.findElements('apis').firstOrNull?.findElements('api') ??
              <XmlElement>[]) {
        apis.add((
          name: api.getAttribute('name') ?? '',
          preferred: api.getAttribute('preferred') == 'true',
          blogId: api.getAttribute('blogID') ?? '',
          link: api.getAttribute('apiLink') ?? '',
        ));
      }

      XmlRpcFlavor flavorFor(String name) => switch (name.toLowerCase()) {
            'wordpress' || 'wp' => XmlRpcFlavor.wordpress,
            'movabletype' || 'mt' => XmlRpcFlavor.movabletype,
            'metaweblog' => XmlRpcFlavor.metaweblog,
            'blogger' => XmlRpcFlavor.blogger,
            _ => XmlRpcFlavor.metaweblog,
          };

      // Prefer: preferred WordPress > WordPress > preferred > first.
      final chosen =
          apis.firstWhereOrNull((a) => a.preferred && a.name.toLowerCase() == 'wordpress') ??
              apis.firstWhereOrNull((a) => a.name.toLowerCase() == 'wordpress') ??
              apis.firstWhereOrNull((a) => a.preferred) ??
              apis.firstOrNull;

      if (chosen == null || chosen.link.isEmpty) return null;
      return BlogDetection(
        homepageUrl: '',
        xmlrpcUrl: chosen.link,
        flavor: flavorFor(chosen.name),
        blogId: chosen.blogId.isEmpty ? null : chosen.blogId,
        engineName: engineName,
      );
    } catch (_) {
      return null;
    }
  }

  void close() => _http.close();
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
