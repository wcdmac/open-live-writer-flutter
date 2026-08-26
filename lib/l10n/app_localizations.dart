import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Live Writer'**
  String get appTitle;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Open Live Writer'**
  String get welcome;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to your WordPress blog to start writing.'**
  String get welcomeSubtitle;

  /// No description provided for @blogCredentials.
  ///
  /// In en, this message translates to:
  /// **'Blog & credentials'**
  String get blogCredentials;

  /// No description provided for @connectionSettings.
  ///
  /// In en, this message translates to:
  /// **'Connection settings'**
  String get connectionSettings;

  /// No description provided for @chooseBlog.
  ///
  /// In en, this message translates to:
  /// **'Choose blog'**
  String get chooseBlog;

  /// No description provided for @blogUrl.
  ///
  /// In en, this message translates to:
  /// **'Blog homepage URL'**
  String get blogUrl;

  /// No description provided for @blogUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com'**
  String get blogUrlHint;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password / Application Password'**
  String get password;

  /// No description provided for @passwordHelper.
  ///
  /// In en, this message translates to:
  /// **'For REST API use an Application Password (WP Admin → Users → Profile → Application Passwords).'**
  String get passwordHelper;

  /// No description provided for @enterBlogUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter your blog URL'**
  String get enterBlogUrl;

  /// No description provided for @enterUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter your username'**
  String get enterUsername;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterPassword;

  /// No description provided for @detectSettings.
  ///
  /// In en, this message translates to:
  /// **'Detect blog settings'**
  String get detectSettings;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @blogEngine.
  ///
  /// In en, this message translates to:
  /// **'Blog engine'**
  String get blogEngine;

  /// No description provided for @xmlrpcEndpoint.
  ///
  /// In en, this message translates to:
  /// **'XML-RPC endpoint'**
  String get xmlrpcEndpoint;

  /// No description provided for @restApi.
  ///
  /// In en, this message translates to:
  /// **'REST API'**
  String get restApi;

  /// No description provided for @notDetected.
  ///
  /// In en, this message translates to:
  /// **'Not detected'**
  String get notDetected;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @connectionProtocol.
  ///
  /// In en, this message translates to:
  /// **'Connection protocol'**
  String get connectionProtocol;

  /// No description provided for @xmlrpcClassic.
  ///
  /// In en, this message translates to:
  /// **'XML-RPC (classic protocol)'**
  String get xmlrpcClassic;

  /// No description provided for @flavor.
  ///
  /// In en, this message translates to:
  /// **'Flavor'**
  String get flavor;

  /// No description provided for @restV2.
  ///
  /// In en, this message translates to:
  /// **'WordPress REST API v2'**
  String get restV2;

  /// No description provided for @endpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get endpoint;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'not available'**
  String get notAvailable;

  /// No description provided for @xmlrpcFlavor.
  ///
  /// In en, this message translates to:
  /// **'XML-RPC API flavor'**
  String get xmlrpcFlavor;

  /// No description provided for @authentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get authentication;

  /// No description provided for @restAuth401.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed (401). An Application Password is NOT your login password — create one in WP Admin → Users → Profile → Application Passwords (WordPress 5.6+, HTTPS site required). Some hosts strip the Authorization header; if it keeps failing, connect with XML-RPC instead. Details: {error}'**
  String restAuth401(String error);

  /// No description provided for @restJwt404.
  ///
  /// In en, this message translates to:
  /// **'JWT endpoint not found (404). JWT authentication requires the \'JWT Authentication for WP REST API\' plugin to be installed and activated on your site. Use an Application Password instead, or connect with XML-RPC. Details: {error}'**
  String restJwt404(String error);

  /// No description provided for @emptyContentNotice.
  ///
  /// In en, this message translates to:
  /// **'The server returned an empty body for this post (content length 0). If the post has content on the web, the account may lack permission to read it, or the connection protocol doesn\'t provide the content field.'**
  String get emptyContentNotice;

  /// No description provided for @pickFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Pick from device & upload'**
  String get pickFromDevice;

  /// No description provided for @enterImageUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter image URL'**
  String get enterImageUrl;

  /// No description provided for @uploadingImage.
  ///
  /// In en, this message translates to:
  /// **'Uploading image…'**
  String get uploadingImage;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String uploadFailed(Object error);

  /// No description provided for @uploadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File exceeds the server size limit (HTTP 413). Increase nginx client_max_body_size (100m recommended, matching the Cloudflare free tier) and PHP upload_max_filesize / post_max_size on your server, then retry.'**
  String get uploadTooLarge;

  /// No description provided for @imageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image failed to load: make sure it is a direct image URL (not a page), uses https, and the host allows hot-linking.'**
  String get imageLoadFailed;

  /// No description provided for @pickVideoFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Pick video from device & upload'**
  String get pickVideoFromDevice;

  /// No description provided for @enterVideoUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter video URL'**
  String get enterVideoUrl;

  /// No description provided for @uploadingVideo.
  ///
  /// In en, this message translates to:
  /// **'Uploading video…'**
  String get uploadingVideo;

  /// No description provided for @detectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Detection failed: {error}'**
  String detectionFailed(Object error);

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionFailed(Object error);

  /// No description provided for @connectedNoBlogs.
  ///
  /// In en, this message translates to:
  /// **'Connected, but no blogs were returned for these credentials.'**
  String get connectedNoBlogs;

  /// No description provided for @saveAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save account: {error}'**
  String saveAccountFailed(Object error);

  /// No description provided for @newPost.
  ///
  /// In en, this message translates to:
  /// **'New post'**
  String get newPost;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @manageAccounts.
  ///
  /// In en, this message translates to:
  /// **'Manage accounts'**
  String get manageAccounts;

  /// No description provided for @accountsSettings.
  ///
  /// In en, this message translates to:
  /// **'Accounts & settings'**
  String get accountsSettings;

  /// No description provided for @addBlogAccount.
  ///
  /// In en, this message translates to:
  /// **'Add blog account'**
  String get addBlogAccount;

  /// No description provided for @addAnotherBlog.
  ///
  /// In en, this message translates to:
  /// **'Add another blog'**
  String get addAnotherBlog;

  /// No description provided for @removeAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\"'**
  String removeAccount(String name);

  /// No description provided for @noPostsYet.
  ///
  /// In en, this message translates to:
  /// **'No posts yet'**
  String get noPostsYet;

  /// No description provided for @createFirstPost.
  ///
  /// In en, this message translates to:
  /// **'Create your first post with the button below.'**
  String get createFirstPost;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'(untitled)'**
  String get untitled;

  /// No description provided for @page.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get page;

  /// No description provided for @newPostTitle.
  ///
  /// In en, this message translates to:
  /// **'New post'**
  String get newPostTitle;

  /// No description provided for @newPageTitle.
  ///
  /// In en, this message translates to:
  /// **'New page'**
  String get newPageTitle;

  /// No description provided for @editTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit: {title}'**
  String editTitle(String title);

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get saveDraft;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publish;

  /// No description provided for @postSettings.
  ///
  /// In en, this message translates to:
  /// **'Post settings'**
  String get postSettings;

  /// No description provided for @postTitle.
  ///
  /// In en, this message translates to:
  /// **'Post title'**
  String get postTitle;

  /// No description provided for @writePostHint.
  ///
  /// In en, this message translates to:
  /// **'Write your post… (HTML)'**
  String get writePostHint;

  /// No description provided for @write.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get write;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @previewTheme.
  ///
  /// In en, this message translates to:
  /// **'Preview • {name}'**
  String previewTheme(String name);

  /// No description provided for @startWritingHint.
  ///
  /// In en, this message translates to:
  /// **'Start writing to see the live preview…'**
  String get startWritingHint;

  /// No description provided for @statusApplied.
  ///
  /// In en, this message translates to:
  /// **'Status (applied on next publish)'**
  String get statusApplied;

  /// No description provided for @publishDate.
  ///
  /// In en, this message translates to:
  /// **'Publish date'**
  String get publishDate;

  /// No description provided for @immediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get immediately;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @tagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get tagsLabel;

  /// No description provided for @applyTags.
  ///
  /// In en, this message translates to:
  /// **'Apply tags'**
  String get applyTags;

  /// No description provided for @excerpt.
  ///
  /// In en, this message translates to:
  /// **'Excerpt'**
  String get excerpt;

  /// No description provided for @urlSlug.
  ///
  /// In en, this message translates to:
  /// **'URL slug'**
  String get urlSlug;

  /// No description provided for @allowComments.
  ///
  /// In en, this message translates to:
  /// **'Allow comments'**
  String get allowComments;

  /// No description provided for @allowPingbacks.
  ///
  /// In en, this message translates to:
  /// **'Allow pingbacks / trackbacks'**
  String get allowPingbacks;

  /// No description provided for @treatAsPage.
  ///
  /// In en, this message translates to:
  /// **'Treat as page (not post)'**
  String get treatAsPage;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChanges;

  /// No description provided for @discardConfirm.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Leave the editor anyway?'**
  String get discardConfirm;

  /// No description provided for @stay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get stay;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @postPublished.
  ///
  /// In en, this message translates to:
  /// **'Post published{id}.'**
  String postPublished(String id);

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved.'**
  String get draftSaved;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed.'**
  String get saveFailed;

  /// No description provided for @loadingPost.
  ///
  /// In en, this message translates to:
  /// **'Loading post…'**
  String get loadingPost;

  /// No description provided for @loadPostFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load post: {error}'**
  String loadPostFailed(Object error);

  /// No description provided for @bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// No description provided for @italic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italic;

  /// No description provided for @underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underline;

  /// No description provided for @strikethrough.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get strikethrough;

  /// No description provided for @h2.
  ///
  /// In en, this message translates to:
  /// **'Heading 2'**
  String get h2;

  /// No description provided for @h3.
  ///
  /// In en, this message translates to:
  /// **'Heading 3'**
  String get h3;

  /// No description provided for @blockquote.
  ///
  /// In en, this message translates to:
  /// **'Blockquote'**
  String get blockquote;

  /// No description provided for @bulletList.
  ///
  /// In en, this message translates to:
  /// **'Bullet list'**
  String get bulletList;

  /// No description provided for @numberedList.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get numberedList;

  /// No description provided for @insertLink.
  ///
  /// In en, this message translates to:
  /// **'Insert link'**
  String get insertLink;

  /// No description provided for @insertImage.
  ///
  /// In en, this message translates to:
  /// **'Insert image'**
  String get insertImage;

  /// No description provided for @codeBlock.
  ///
  /// In en, this message translates to:
  /// **'Code block'**
  String get codeBlock;

  /// No description provided for @moreTag.
  ///
  /// In en, this message translates to:
  /// **'More tag (excerpt break)'**
  String get moreTag;

  /// No description provided for @copyHtml.
  ///
  /// In en, this message translates to:
  /// **'Copy HTML'**
  String get copyHtml;

  /// No description provided for @linkUrl.
  ///
  /// In en, this message translates to:
  /// **'Link URL'**
  String get linkUrl;

  /// No description provided for @imageUrl.
  ///
  /// In en, this message translates to:
  /// **'Image URL'**
  String get imageUrl;

  /// No description provided for @altText.
  ///
  /// In en, this message translates to:
  /// **'Alt text (optional)'**
  String get altText;

  /// No description provided for @copyDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get copyDiagnostics;

  /// No description provided for @diagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied to clipboard'**
  String get diagnosticsCopied;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @postStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get postStatusDraft;

  /// No description provided for @postStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get postStatusPending;

  /// No description provided for @postStatusPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get postStatusPrivate;

  /// No description provided for @postStatusPublish.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get postStatusPublish;

  /// No description provided for @postStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get postStatusScheduled;

  /// No description provided for @postStatusTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get postStatusTrash;

  /// No description provided for @protocolXmlrpc.
  ///
  /// In en, this message translates to:
  /// **'XML-RPC'**
  String get protocolXmlrpc;

  /// No description provided for @protocolRest.
  ///
  /// In en, this message translates to:
  /// **'REST API v2'**
  String get protocolRest;

  /// No description provided for @flavorWordpress.
  ///
  /// In en, this message translates to:
  /// **'WordPress'**
  String get flavorWordpress;

  /// No description provided for @flavorMetaweblog.
  ///
  /// In en, this message translates to:
  /// **'MetaWeblog'**
  String get flavorMetaweblog;

  /// No description provided for @flavorMovabletype.
  ///
  /// In en, this message translates to:
  /// **'MovableType'**
  String get flavorMovabletype;

  /// No description provided for @flavorBlogger.
  ///
  /// In en, this message translates to:
  /// **'Blogger'**
  String get flavorBlogger;

  /// No description provided for @authAppPassword.
  ///
  /// In en, this message translates to:
  /// **'Application Password'**
  String get authAppPassword;

  /// No description provided for @authJwt.
  ///
  /// In en, this message translates to:
  /// **'JWT Bearer'**
  String get authJwt;

  /// No description provided for @visualMode.
  ///
  /// In en, this message translates to:
  /// **'Visual'**
  String get visualMode;

  /// No description provided for @sourceMode.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourceMode;

  /// No description provided for @addBlock.
  ///
  /// In en, this message translates to:
  /// **'Insert block'**
  String get addBlock;

  /// No description provided for @paragraphBlock.
  ///
  /// In en, this message translates to:
  /// **'Paragraph'**
  String get paragraphBlock;

  /// No description provided for @headingBlock.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get headingBlock;

  /// No description provided for @imageBlock.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get imageBlock;

  /// No description provided for @tableBlock.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get tableBlock;

  /// No description provided for @videoBlock.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get videoBlock;

  /// No description provided for @videoUrl.
  ///
  /// In en, this message translates to:
  /// **'Video URL'**
  String get videoUrl;

  /// No description provided for @videoUrlHint.
  ///
  /// In en, this message translates to:
  /// **'YouTube link, direct .mp4, or embeddable page'**
  String get videoUrlHint;

  /// No description provided for @tableHeaderRow.
  ///
  /// In en, this message translates to:
  /// **'First row is header'**
  String get tableHeaderRow;

  /// No description provided for @tableBorder.
  ///
  /// In en, this message translates to:
  /// **'Borders'**
  String get tableBorder;

  /// No description provided for @addRow.
  ///
  /// In en, this message translates to:
  /// **'Add row'**
  String get addRow;

  /// No description provided for @addColumn.
  ///
  /// In en, this message translates to:
  /// **'Add column'**
  String get addColumn;

  /// No description provided for @removeRow.
  ///
  /// In en, this message translates to:
  /// **'Remove row'**
  String get removeRow;

  /// No description provided for @removeColumn.
  ///
  /// In en, this message translates to:
  /// **'Remove column'**
  String get removeColumn;

  /// No description provided for @deleteBlock.
  ///
  /// In en, this message translates to:
  /// **'Delete block'**
  String get deleteBlock;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @captionLabel.
  ///
  /// In en, this message translates to:
  /// **'Caption (optional)'**
  String get captionLabel;

  /// No description provided for @emptyBlockHint.
  ///
  /// In en, this message translates to:
  /// **'Type here…'**
  String get emptyBlockHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
