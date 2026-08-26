// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Open Live Writer';

  @override
  String get welcome => '欢迎使用 Open Live Writer';

  @override
  String get welcomeSubtitle => '连接到你的 WordPress 博客开始写作。';

  @override
  String get blogCredentials => '博客与凭据';

  @override
  String get connectionSettings => '连接设置';

  @override
  String get chooseBlog => '选择博客';

  @override
  String get blogUrl => '博客首页地址';

  @override
  String get blogUrlHint => 'https://example.com';

  @override
  String get username => '用户名';

  @override
  String get password => '密码 / 应用程序密码';

  @override
  String get passwordHelper =>
      'REST API 请使用应用程序密码（WP 后台 → 用户 → 个人资料 → 应用程序密码）。';

  @override
  String get enterBlogUrl => '请输入博客地址';

  @override
  String get enterUsername => '请输入用户名';

  @override
  String get enterPassword => '请输入密码';

  @override
  String get detectSettings => '检测博客设置';

  @override
  String get connect => '连接';

  @override
  String get finish => '完成';

  @override
  String get back => '返回';

  @override
  String get blogEngine => '博客引擎';

  @override
  String get xmlrpcEndpoint => 'XML-RPC 端点';

  @override
  String get restApi => 'REST API';

  @override
  String get notDetected => '未检测到';

  @override
  String get unknown => '未知';

  @override
  String get connectionProtocol => '连接协议';

  @override
  String get xmlrpcClassic => 'XML-RPC（经典协议）';

  @override
  String get flavor => '类型';

  @override
  String get restV2 => 'WordPress REST API v2';

  @override
  String get endpoint => '端点';

  @override
  String get notAvailable => '不可用';

  @override
  String get xmlrpcFlavor => 'XML-RPC API 类型';

  @override
  String get authentication => '认证方式';

  @override
  String restAuth401(String error) {
    return '认证失败（401）。应用程序密码不是登录密码——请在 WP 后台 → 用户 → 个人资料 → 应用程序密码 中创建（需 WordPress 5.6+ 且网站为 HTTPS）。部分主机会丢弃 Authorization 请求头导致认证失败，如持续失败请改用 XML-RPC 连接。详情：$error';
  }

  @override
  String restJwt404(String error) {
    return '未找到 JWT 端点（404）。JWT 认证需要在站点安装并启用「JWT Authentication for WP REST API」插件。请改用应用程序密码认证，或使用 XML-RPC 连接。详情：$error';
  }

  @override
  String get emptyContentNotice =>
      '服务器返回了空的文章正文（内容长度为 0）。如果该文章在网页上有内容，可能是当前账号缺少阅读权限，或所选连接协议未提供正文字段。';

  @override
  String get pickFromDevice => '从设备选择并上传';

  @override
  String get enterImageUrl => '输入图片 URL';

  @override
  String get uploadingImage => '正在上传图片…';

  @override
  String uploadFailed(Object error) {
    return '上传失败：$error';
  }

  @override
  String get uploadTooLarge =>
      '文件超过服务器大小限制（HTTP 413）。请在服务器上调大 nginx 的 client_max_body_size（建议 100m，与 Cloudflare 免费版一致）以及 PHP 的 upload_max_filesize 和 post_max_size，然后重试。';

  @override
  String get imageLoadFailed => '图片无法加载：请确认是图片直链（不是网页地址）、使用 https，且图床未设置防盗链。';

  @override
  String get pickVideoFromDevice => '从设备选择视频并上传';

  @override
  String get enterVideoUrl => '输入视频地址';

  @override
  String get uploadingVideo => '正在上传视频…';

  @override
  String detectionFailed(Object error) {
    return '检测失败：$error';
  }

  @override
  String connectionFailed(Object error) {
    return '连接失败：$error';
  }

  @override
  String get connectedNoBlogs => '已连接，但这些凭据没有返回任何博客。';

  @override
  String saveAccountFailed(Object error) {
    return '保存账户失败：$error';
  }

  @override
  String get newPost => '新建文章';

  @override
  String get refresh => '刷新';

  @override
  String get manageAccounts => '管理账户';

  @override
  String get accountsSettings => '账户与设置';

  @override
  String get addBlogAccount => '添加博客账户';

  @override
  String get addAnotherBlog => '添加其他博客';

  @override
  String removeAccount(String name) {
    return '移除「$name」';
  }

  @override
  String get noPostsYet => '暂无文章';

  @override
  String get createFirstPost => '使用下方按钮创建你的第一篇文章。';

  @override
  String get retry => '重试';

  @override
  String get untitled => '（无标题）';

  @override
  String get page => '页面';

  @override
  String get newPostTitle => '新建文章';

  @override
  String get newPageTitle => '新建页面';

  @override
  String editTitle(String title) {
    return '编辑：$title';
  }

  @override
  String get saveDraft => '存为草稿';

  @override
  String get publish => '发布';

  @override
  String get postActions => '文章操作';

  @override
  String get editPost => '编辑';

  @override
  String get moveToDraft => '转为草稿';

  @override
  String get setAsPrivate => '设为私有';

  @override
  String get moveToTrash => '删除（移入回收站）';

  @override
  String deletePostConfirm(Object title) {
    return '将《$title》移入回收站？可在 WordPress 后台的回收站中恢复。';
  }

  @override
  String operationFailed(Object error) {
    return '操作失败：$error';
  }

  @override
  String get postSettings => '文章设置';

  @override
  String get postTitle => '文章标题';

  @override
  String get writePostHint => '撰写文章…（HTML）';

  @override
  String get write => '撰写';

  @override
  String get preview => '预览';

  @override
  String previewTheme(String name) {
    return '预览 • $name';
  }

  @override
  String get startWritingHint => '开始写作以查看实时预览…';

  @override
  String get statusApplied => '状态（下次发布时应用）';

  @override
  String get publishDate => '发布日期';

  @override
  String get immediately => '立即';

  @override
  String get categories => '分类';

  @override
  String get tagsLabel => '标签（逗号分隔）';

  @override
  String get applyTags => '应用标签';

  @override
  String get excerpt => '摘要';

  @override
  String get urlSlug => 'URL 别名';

  @override
  String get allowComments => '允许评论';

  @override
  String get allowPingbacks => '允许 Pingback / Trackback';

  @override
  String get treatAsPage => '作为页面（非文章）';

  @override
  String get discardChanges => '放弃更改？';

  @override
  String get discardConfirm => '你有未保存的更改。仍要离开编辑器？';

  @override
  String get stay => '留下';

  @override
  String get discard => '放弃';

  @override
  String postPublished(String id) {
    return '文章已发布$id。';
  }

  @override
  String get draftSaved => '草稿已保存。';

  @override
  String get saveFailed => '保存失败。';

  @override
  String get loadingPost => '加载文章中…';

  @override
  String loadPostFailed(Object error) {
    return '加载文章失败：$error';
  }

  @override
  String get bold => '加粗';

  @override
  String get italic => '斜体';

  @override
  String get underline => '下划线';

  @override
  String get strikethrough => '删除线';

  @override
  String get h2 => '二级标题';

  @override
  String get h3 => '三级标题';

  @override
  String get blockquote => '引用';

  @override
  String get bulletList => '无序列表';

  @override
  String get numberedList => '有序列表';

  @override
  String get insertLink => '插入链接';

  @override
  String get insertImage => '插入图片';

  @override
  String get codeBlock => '代码';

  @override
  String get moreTag => '更多标签（摘要分隔）';

  @override
  String get copyHtml => '复制 HTML';

  @override
  String get linkUrl => '链接地址';

  @override
  String get imageUrl => '图片地址';

  @override
  String get altText => '替代文本（可选）';

  @override
  String get alignLeft => '左对齐';

  @override
  String get alignCenter => '居中';

  @override
  String get alignRight => '右对齐';

  @override
  String get cancel => '取消';

  @override
  String get ok => '确定';

  @override
  String get postStatusDraft => '草稿';

  @override
  String get postStatusPending => '待审';

  @override
  String get postStatusPrivate => '私有';

  @override
  String get postStatusPublish => '已发布';

  @override
  String get postStatusScheduled => '已排期';

  @override
  String get postStatusTrash => '回收站';

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
  String get authAppPassword => '应用程序密码';

  @override
  String get authJwt => 'JWT Bearer';

  @override
  String get visualMode => '可视化';

  @override
  String get sourceMode => '源代码';

  @override
  String get addBlock => '插入块';

  @override
  String get paragraphBlock => '段落';

  @override
  String get headingBlock => '标题';

  @override
  String get imageBlock => '图片';

  @override
  String get tableBlock => '表格';

  @override
  String get videoBlock => '视频';

  @override
  String get videoUrl => '视频地址';

  @override
  String get videoUrlHint => 'YouTube 链接、MP4 直链或可嵌入页面';

  @override
  String get tableHeaderRow => '首行为表头';

  @override
  String get tableBorder => '边框';

  @override
  String get addRow => '加一行';

  @override
  String get addColumn => '加一列';

  @override
  String get removeRow => '删一行';

  @override
  String get removeColumn => '删一列';

  @override
  String get deleteBlock => '删除此块';

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get captionLabel => '图片说明（可选）';

  @override
  String get emptyBlockHint => '在此输入…';

  @override
  String get listBlock => '列表';

  @override
  String get quoteBlock => '引用';

  @override
  String get removeItem => '删除此项';

  @override
  String get addItem => '添加一项';

  @override
  String get addParagraph => '添加段落';

  @override
  String get postPassword => '文章密码';

  @override
  String get postPasswordHelp => '读者需输入此密码才能查看文章（留空 = 不加保护）';

  @override
  String get newCategory => '新建分类';

  @override
  String get newCategoryHint => '分类名称';

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String charCount(num count) {
    return '$count 字';
  }

  @override
  String get saveLocalDraft => '保存到本地草稿';

  @override
  String get saveLocalDraftHelp => '仅保存在本机，联网后再发布';

  @override
  String get savedOfflineDraft => '网络不可用——草稿已保存到本地，稍后可从首页发布。';

  @override
  String localDraftSubtitle(String time) {
    return '本地草稿 · $time · 未同步';
  }

  @override
  String get deleteDraftTitle => '删除本地草稿';

  @override
  String deleteDraftConfirm(Object title) {
    return '永久删除本地草稿《$title》？该草稿尚未上传，删除后无法恢复。';
  }

  @override
  String offlineCopySubtitle(String time) {
    return '离线副本 · $time · 可离线编辑';
  }

  @override
  String get deleteLocalCopy => '删除本地副本';

  @override
  String get syncNow => '立即同步到博客';

  @override
  String get syncedToBlog => '已同步到博客';

  @override
  String get saveOfflineCopy => '保存到本地（离线副本）';

  @override
  String get saveOfflineCopyHelp => '下载全文到本机，断网也能查看和编辑';

  @override
  String get savedOfflineCopy => '已保存离线副本，断网时也可编辑';

  @override
  String get exportPost => '导出文章';

  @override
  String get exportFormatHint => '选择导出格式：HTML 保留区块标记，Markdown 便于通用编辑。';

  @override
  String get markdownFormat => 'Markdown';

  @override
  String get htmlFormat => 'HTML';

  @override
  String get exportDoneTitle => '导出完成';

  @override
  String get exportAllWxr => '导出全部文章（WXR）';

  @override
  String get exportAllWxrHelp => '生成 WordPress 标准导出文件，可在后台重新导入';

  @override
  String get exportingPosts => '正在拉取全部文章…';

  @override
  String get crashRecoveryTitle => '发现未保存的内容';

  @override
  String crashRecoveryBody(String time) {
    return '检测到 $time 未保存的草稿，是否恢复？';
  }

  @override
  String get restore => '恢复';

  @override
  String get delete => '删除';
}
