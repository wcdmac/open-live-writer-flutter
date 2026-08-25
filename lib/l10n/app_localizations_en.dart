// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Open Live Writer';

  @override
  String get welcome => 'Welcome to Open Live Writer';

  @override
  String get welcomeSubtitle =>
      'Connect to your WordPress blog to start writing.';

  @override
  String get blogCredentials => 'Blog & credentials';

  @override
  String get connectionSettings => 'Connection settings';

  @override
  String get chooseBlog => 'Choose blog';

  @override
  String get blogUrl => 'Blog homepage URL';

  @override
  String get blogUrlHint => 'https://example.com';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password / Application Password';

  @override
  String get passwordHelper =>
      'For REST API use an Application Password (WP Admin → Users → Profile → Application Passwords).';

  @override
  String get enterBlogUrl => 'Enter your blog URL';

  @override
  String get enterUsername => 'Enter your username';

  @override
  String get enterPassword => 'Enter your password';

  @override
  String get detectSettings => 'Detect blog settings';

  @override
  String get connect => 'Connect';

  @override
  String get finish => 'Finish';

  @override
  String get back => 'Back';

  @override
  String get blogEngine => 'Blog engine';

  @override
  String get xmlrpcEndpoint => 'XML-RPC endpoint';

  @override
  String get restApi => 'REST API';

  @override
  String get notDetected => 'Not detected';

  @override
  String get unknown => 'Unknown';

  @override
  String get connectionProtocol => 'Connection protocol';

  @override
  String get xmlrpcClassic => 'XML-RPC (classic Open Live Writer)';

  @override
  String get flavor => 'Flavor';

  @override
  String get restV2 => 'WordPress REST API v2';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get notAvailable => 'not available';

  @override
  String get xmlrpcFlavor => 'XML-RPC API flavor';

  @override
  String get authentication => 'Authentication';

  @override
  String detectionFailed(Object error) {
    return 'Detection failed: $error';
  }

  @override
  String connectionFailed(Object error) {
    return 'Connection failed: $error';
  }

  @override
  String get connectedNoBlogs =>
      'Connected, but no blogs were returned for these credentials.';

  @override
  String saveAccountFailed(Object error) {
    return 'Failed to save account: $error';
  }

  @override
  String get newPost => 'New post';

  @override
  String get refresh => 'Refresh';

  @override
  String get manageAccounts => 'Manage accounts';

  @override
  String get accountsSettings => 'Accounts & settings';

  @override
  String get addBlogAccount => 'Add blog account';

  @override
  String get addAnotherBlog => 'Add another blog';

  @override
  String removeAccount(String name) {
    return 'Remove \"$name\"';
  }

  @override
  String get noPostsYet => 'No posts yet';

  @override
  String get createFirstPost => 'Create your first post with the button below.';

  @override
  String get retry => 'Retry';

  @override
  String get untitled => '(untitled)';

  @override
  String get page => 'Page';

  @override
  String get newPostTitle => 'New post';

  @override
  String get newPageTitle => 'New page';

  @override
  String editTitle(String title) {
    return 'Edit: $title';
  }

  @override
  String get saveDraft => 'Save draft';

  @override
  String get publish => 'Publish';

  @override
  String get postSettings => 'Post settings';

  @override
  String get postTitle => 'Post title';

  @override
  String get writePostHint => 'Write your post… (HTML)';

  @override
  String get write => 'Write';

  @override
  String get preview => 'Preview';

  @override
  String previewTheme(String name) {
    return 'Preview • $name';
  }

  @override
  String get startWritingHint => 'Start writing to see the live preview…';

  @override
  String get statusApplied => 'Status (applied on next publish)';

  @override
  String get publishDate => 'Publish date';

  @override
  String get immediately => 'Immediately';

  @override
  String get categories => 'Categories';

  @override
  String get tagsLabel => 'Tags (comma separated)';

  @override
  String get applyTags => 'Apply tags';

  @override
  String get excerpt => 'Excerpt';

  @override
  String get urlSlug => 'URL slug';

  @override
  String get allowComments => 'Allow comments';

  @override
  String get allowPingbacks => 'Allow pingbacks / trackbacks';

  @override
  String get treatAsPage => 'Treat as page (not post)';

  @override
  String get discardChanges => 'Discard changes?';

  @override
  String get discardConfirm =>
      'You have unsaved changes. Leave the editor anyway?';

  @override
  String get stay => 'Stay';

  @override
  String get discard => 'Discard';

  @override
  String postPublished(String id) {
    return 'Post published$id.';
  }

  @override
  String get draftSaved => 'Draft saved.';

  @override
  String get saveFailed => 'Save failed.';

  @override
  String get loadingPost => 'Loading post…';

  @override
  String loadPostFailed(Object error) {
    return 'Failed to load post: $error';
  }

  @override
  String get bold => 'Bold';

  @override
  String get italic => 'Italic';

  @override
  String get underline => 'Underline';

  @override
  String get strikethrough => 'Strikethrough';

  @override
  String get h2 => 'Heading 2';

  @override
  String get h3 => 'Heading 3';

  @override
  String get blockquote => 'Blockquote';

  @override
  String get bulletList => 'Bullet list';

  @override
  String get numberedList => 'Numbered list';

  @override
  String get insertLink => 'Insert link';

  @override
  String get insertImage => 'Insert image';

  @override
  String get codeBlock => 'Code block';

  @override
  String get moreTag => 'More tag (excerpt break)';

  @override
  String get copyHtml => 'Copy HTML';

  @override
  String get linkUrl => 'Link URL';

  @override
  String get imageUrl => 'Image URL';

  @override
  String get altText => 'Alt text (optional)';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get postStatusDraft => 'Draft';

  @override
  String get postStatusPending => 'Pending review';

  @override
  String get postStatusPrivate => 'Private';

  @override
  String get postStatusPublish => 'Published';

  @override
  String get postStatusScheduled => 'Scheduled';

  @override
  String get postStatusTrash => 'Trash';

  @override
  String get protocolXmlrpc => 'XML-RPC';

  @override
  String get protocolRest => 'REST API v2';

  @override
  String get flavorWordpress => 'WordPress';

  @override
  String get flavorMetaweblog => 'MetaWeblog';

  @override
  String get flavorMovabletype => 'MovableType';

  @override
  String get flavorBlogger => 'Blogger';

  @override
  String get authAppPassword => 'Application Password';

  @override
  String get authJwt => 'JWT Bearer';
}
