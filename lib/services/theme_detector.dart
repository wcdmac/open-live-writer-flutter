import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

/// Typography / palette extracted from the live blog theme, used by the
/// real-time preview so posts look the way they will on the site.
class BlogTheme {
  const BlogTheme({
    this.name,
    this.fontFamily,
    this.bodyColor = 'rgba(0, 0, 0, 0.87)',
    this.headingColor = 'rgba(0, 0, 0, 0.89)',
    this.linkColor = '#2563eb',
    this.backgroundColor = '#ffffff',
    this.contentWidth = 720,
  });

  final String? name;
  final String? fontFamily;
  final String bodyColor;
  final String headingColor;
  final String linkColor;
  final String backgroundColor;
  final double contentWidth;

  BlogTheme copyWith({
    String? name,
    String? fontFamily,
    String? bodyColor,
    String? headingColor,
    String? linkColor,
    String? backgroundColor,
    double? contentWidth,
  }) =>
      BlogTheme(
        name: name ?? this.name,
        fontFamily: fontFamily ?? this.fontFamily,
        bodyColor: bodyColor ?? this.bodyColor,
        headingColor: headingColor ?? this.headingColor,
        linkColor: linkColor ?? this.linkColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        contentWidth: contentWidth ?? this.contentWidth,
      );
}

/// Fetches the blog homepage, locates the active theme stylesheet and
/// extracts the essentials for a faithful preview.
///
/// This replaces the original's BlogEditingTemplateDetector which had to
/// temporarily publish a post and re-download it to obtain the surrounding
/// theme HTML — instead we read the theme CSS directly, with no side
/// effects on the blog.
class ThemeDetector {
  ThemeDetector({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<BlogTheme> detect(String homepageUrl) async {
    try {
      final res = await _http.get(Uri.parse(homepageUrl)).timeout(_timeout);
      final doc = html_parser.parse(res.body);

      final base = Uri.parse(homepageUrl);
      String? themeName;
      final cssUrls = <String>[];

      for (final link in doc.querySelectorAll('link[rel="stylesheet"]')) {
        final href = link.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        final absolute = base.resolve(href).toString();
        cssUrls.add(absolute);
        final m = RegExp(r'/themes/([^/]+)/').firstMatch(absolute);
        if (m != null && themeName == null) {
          themeName = m.group(1);
        }
      }

      // Inspect the theme's main stylesheet (usually the one under
      // /wp-content/themes/<name>/).
      final themeCssUrl = cssUrls
          .where((u) => u.contains('/themes/'))
          .firstOrNull;
      if (themeCssUrl != null) {
        final css = await _fetchCss(themeCssUrl);
        if (css != null) {
          return _themeFromCss(css)
              .copyWith(name: themeName ?? 'WordPress theme');
        }
      }

      return BlogTheme(name: themeName);
    } catch (_) {
      return const BlogTheme(name: 'Default');
    }
  }

  Future<String?> _fetchCss(String url) async {
    try {
      final res = await _http.get(Uri.parse(url)).timeout(_timeout);
      return res.statusCode == 200 ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts preview-relevant declarations from a theme stylesheet.
  BlogTheme _themeFromCss(String css) {
    String? font;
    String? bodyColor;
    String? linkColor;
    String? headingColor;
    String? background;
    double? contentWidth;

    String? decl(String selector, String property) {
      // Match `selector { ... property: value; ... }` (single rules only —
      // good enough for a best-effort theme probe).
      final rule = RegExp(
        RegExp.escape(selector) + r'\s*\{([^}]*)\}',
        multiLine: true,
      ).firstMatch(css);
      if (rule == null) return null;
      final prop = RegExp(
        property + r'\s*:\s*([^;}]+)',
        caseSensitive: false,
      ).firstMatch(rule.group(1)!);
      return prop?.group(1)?.trim();
    }

    font = decl('body', 'font-family') ?? font;
    bodyColor = decl('body', 'color');
    background = decl('body', 'background-color') ??
        (decl('body', 'background')?.startsWith('#') == true ||
                RegExp(r'^[a-z]+\s*$').hasMatch(decl('body', 'background') ?? '')
            ? decl('body', 'background')
            : null);
    linkColor = decl('a', 'color') ??
        decl('a:link', 'color') ??
        decl('.entry-content a', 'color');
    headingColor = decl('h1', 'color') ??
        decl('h2', 'color') ??
        decl('.entry-title', 'color');

    final widthDecl = decl('.entry-content', 'max-width') ??
        decl('.site-content', 'max-width') ??
        decl('#content', 'max-width');
    if (widthDecl != null) {
      final px = RegExp(r'(\d+(?:\.\d+)?)px').firstMatch(widthDecl);
      if (px != null) contentWidth = double.tryParse(px.group(1)!);
    }

    final defaults = const BlogTheme();
    return BlogTheme(
      fontFamily: font,
      bodyColor: bodyColor ?? defaults.bodyColor,
      headingColor: headingColor ?? defaults.headingColor,
      linkColor: linkColor ?? defaults.linkColor,
      backgroundColor: background ?? defaults.backgroundColor,
      contentWidth: contentWidth ?? defaults.contentWidth,
    );
  }

  void close() => _http.close();
}
