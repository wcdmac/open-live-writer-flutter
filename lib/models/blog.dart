/// Connection protocol used to talk to the blog.
enum BlogProtocol {
  /// Classic XML-RPC endpoints (WordPress API, MetaWeblog, Blogger, MovableType).
  xmlrpc,

  /// WordPress REST API v2 (application passwords / JWT / cookie auth).
  rest;

  String get label => switch (this) {
        BlogProtocol.xmlrpc => 'XML-RPC',
        BlogProtocol.rest => 'REST API v2',
      };

  static BlogProtocol fromName(String? name) =>
      name == 'rest' ? BlogProtocol.rest : BlogProtocol.xmlrpc;
}

/// XML-RPC API flavor, mirroring the original Open Live Writer providers.
enum XmlRpcFlavor {
  wordpress,
  metaweblog,
  movabletype,
  blogger;

  String get label => switch (this) {
        XmlRpcFlavor.wordpress => 'WordPress',
        XmlRpcFlavor.metaweblog => 'MetaWeblog',
        XmlRpcFlavor.movabletype => 'MovableType',
        XmlRpcFlavor.blogger => 'Blogger',
      };

  static XmlRpcFlavor fromName(String? name) {
    final n = (name ?? '').toLowerCase();
    if (n.contains('wordpress') || n.contains('wp')) {
      return XmlRpcFlavor.wordpress;
    }
    if (n.contains('movable') || n == 'mt') return XmlRpcFlavor.movabletype;
    if (n.contains('blogger')) return XmlRpcFlavor.blogger;
    return XmlRpcFlavor.metaweblog;
  }
}

/// REST API authentication strategy.
enum RestAuthMethod {
  /// Basic auth with WordPress Application Passwords.
  applicationPassword,

  /// JWT Bearer tokens (jwt-auth plugin).
  jwt;

  static RestAuthMethod fromName(String? name) =>
      name == 'jwt' ? RestAuthMethod.jwt : RestAuthMethod.applicationPassword;

  String get label => switch (this) {
        RestAuthMethod.applicationPassword => 'Application Password',
        RestAuthMethod.jwt => 'JWT Bearer',
      };
}

/// A blog discovered on a user's account (result of getUsersBlogs).
class BlogInfo {
  const BlogInfo({
    required this.blogId,
    required this.name,
    required this.url,
    this.xmlrpcUrl,
  });

  final String blogId;
  final String name;
  final String url;
  final String? xmlrpcUrl;

  factory BlogInfo.fromXmlRpcStruct(Map<dynamic, dynamic> struct) => BlogInfo(
        blogId: '${struct['blogid'] ?? struct['blogId'] ?? ''}',
        name: '${struct['blogName'] ?? struct['name'] ?? ''}',
        url: '${struct['url'] ?? ''}',
        xmlrpcUrl: struct['xmlrpc'] == null ? null : '${struct['xmlrpc']}',
      );
}

/// A locally stored blog account. Credentials live in secure storage
/// keyed by [id]; they are never persisted inside this model.
class BlogAccount {
  BlogAccount({
    required this.id,
    required this.blogId,
    required this.name,
    required this.homepageUrl,
    required this.apiUrl,
    required this.protocol,
    required this.username,
    this.flavor = XmlRpcFlavor.wordpress,
    this.restAuth = RestAuthMethod.applicationPassword,
    this.themeCssUrl,
    this.themeName,
  });

  final String id;
  final String blogId;
  final String name;
  final String homepageUrl;
  final String apiUrl;
  final BlogProtocol protocol;
  final String username;

  /// XML-RPC flavor used when [protocol] is xmlrpc.
  final XmlRpcFlavor flavor;

  /// REST auth strategy used when [protocol] is rest.
  final RestAuthMethod restAuth;

  /// Detected theme stylesheet (used by the live preview).
  final String? themeCssUrl;
  final String? themeName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'blogId': blogId,
        'name': name,
        'homepageUrl': homepageUrl,
        'apiUrl': apiUrl,
        'protocol': protocol.name,
        'username': username,
        'flavor': flavor.name,
        'restAuth': restAuth.name,
        'themeCssUrl': themeCssUrl,
        'themeName': themeName,
      };

  factory BlogAccount.fromJson(Map<String, dynamic> json) => BlogAccount(
        id: json['id'] as String,
        blogId: json['blogId'] as String? ?? '1',
        name: json['name'] as String? ?? 'Blog',
        homepageUrl: json['homepageUrl'] as String? ?? '',
        apiUrl: json['apiUrl'] as String? ?? '',
        protocol: BlogProtocol.fromName(json['protocol'] as String?),
        username: json['username'] as String? ?? '',
        flavor: XmlRpcFlavor.fromName(json['flavor'] as String?),
        restAuth: RestAuthMethod.fromName(json['restAuth'] as String?),
        themeCssUrl: json['themeCssUrl'] as String?,
        themeName: json['themeName'] as String?,
      );

  BlogAccount copyWith({
    String? blogId,
    String? name,
    String? homepageUrl,
    String? apiUrl,
    BlogProtocol? protocol,
    String? username,
    XmlRpcFlavor? flavor,
    RestAuthMethod? restAuth,
    String? themeCssUrl,
    String? themeName,
  }) =>
      BlogAccount(
        id: id,
        blogId: blogId ?? this.blogId,
        name: name ?? this.name,
        homepageUrl: homepageUrl ?? this.homepageUrl,
        apiUrl: apiUrl ?? this.apiUrl,
        protocol: protocol ?? this.protocol,
        username: username ?? this.username,
        flavor: flavor ?? this.flavor,
        restAuth: restAuth ?? this.restAuth,
        themeCssUrl: themeCssUrl ?? this.themeCssUrl,
        themeName: themeName ?? this.themeName,
      );
}
