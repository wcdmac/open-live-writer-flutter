import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/blog.dart';
import '../models/blog_post.dart';
import '../services/local_draft_store.dart';
import '../services/post_exporter.dart';
import '../state/app_state.dart';
import 'add_account_page.dart';
import 'post_editor_page.dart';

/// Dashboard: blog switcher + post list, mirroring OLW's main window.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Notifier bumped after each fetched page so the WXR export dialog
  /// re-renders its progress text.
  final _exportProgress = ValueNotifier<int>(0);

  @override
  void dispose() {
    _exportProgress.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      if (app.hasAccount &&
          app.posts.isEmpty &&
          !app.loading &&
          app.error == null) {
        app.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = AppLocalizations.of(context)!;

    if (!app.hasAccount) {
      return const AddAccountPage(embedded: true);
    }

    return Scaffold(
      appBar: AppBar(
        title: _BlogSwitcher(app: app),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            icon: app.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: app.loading ? null : () => app.refresh(),
          ),
          IconButton(
            tooltip: l10n.manageAccounts,
            icon: const Icon(Icons.settings),
            onPressed: () => _openAccountSettings(context, app),
          ),
        ],
      ),
      body: _buildBody(context, app),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit),
        label: Text(l10n.newPost),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PostEditorPage()),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppState app) {
    final l10n = AppLocalizations.of(context)!;
    final hasDrafts = app.localDrafts.isNotEmpty;
    if (app.error != null && app.posts.isEmpty && !hasDrafts) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                app.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => app.refresh(),
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (app.loading && app.posts.isEmpty && !hasDrafts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (app.posts.isEmpty && !hasDrafts) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined,
                size: 56, color: Theme.of(context).disabledColor),
            const SizedBox(height: 8),
            Text(l10n.noPostsYet,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.createFirstPost),
          ],
        ),
      );
    }

    // Local drafts pin to the top: offline work stays reachable even when
    // the blog is unreachable.
    return RefreshIndicator(
      onRefresh: () => app.refresh(),
      child: ListView.separated(
        itemCount: app.localDrafts.length + app.posts.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index < app.localDrafts.length) {
            return _LocalDraftTile(draft: app.localDrafts[index], app: app);
          }
          final post = app.posts[index - app.localDrafts.length];
          return _PostTile(post: post, app: app);
        },
      ),
    );
  }

  Future<void> _openAccountSettings(BuildContext context, AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Sheet entries must pop `sheetContext` but run follow-up actions
      // with the OUTER `context`: the sheet's own context dies with its
      // exit animation, and an async continuation using it (export) saw
      // context.mounted == false and silently returned, leaving the
      // progress dialog spinning forever even though the fetch had
      // already finished.
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.accountsSettings,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...app.accounts.map((account) => ListTile(
                  leading: CircleAvatar(
                    child: Text(account.name.isEmpty
                        ? '?'
                        : account.name[0].toUpperCase()),
                  ),
                  title: Text(account.name),
                  subtitle: Text(
                    '${account.username} • ${protocolLabel(l10n, account.protocol)}'
                    '${account.protocol == BlogProtocol.xmlrpc ? ' (${flavorLabel(l10n, account.flavor)})' : ''}',
                  ),
                  trailing: account.id == app.currentAccount?.id
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () {
                    app.selectAccount(account);
                    Navigator.of(sheetContext).pop();
                  },
                )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.addBlogAccount),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const AddAccountPage(embedded: false)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(l10n.exportAllWxr),
              subtitle: Text(l10n.exportAllWxrHelp),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _exportAllWxr(context, app);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n
                  .removeAccount(app.currentAccount?.name ?? '')),
              onTap: () {
                final id = app.currentAccount?.id;
                Navigator.of(sheetContext).pop();
                if (id != null) app.removeAccount(id);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Whole-blog export: fetches every post (paged) and writes a WXR
  /// file the WordPress admin can re-import. Progress is shown per
  /// page; the dialog can be cancelled mid-fetch.
  Future<void> _exportAllWxr(BuildContext context, AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    final account = app.currentAccount;
    final svc = app.service;
    if (account == null || svc == null) return;
    // Captured BEFORE any await: async continuations below must not
    // touch a context that may have been unmounted in the meantime.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var cancelled = false;
    var dialogOpen = true;
    var fetched = 0;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: _exportProgress,
                builder: (_, _) => Text(
                  fetched == 0
                      ? l10n.exportingPosts
                      : l10n.exportingPostsProgress(fetched),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                dialogOpen = false;
                Navigator.of(dialogContext).pop();
              },
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
    try {
      final posts = await svc.getAllPosts(
        onProgress: (n) {
          fetched = n;
          _exportProgress.value++;
        },
        shouldCancel: () => cancelled,
      );
      if (cancelled) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.exportCancelled)));
        return;
      }
      final wxr = PostExporter.buildWxr(posts,
          account: account,
          categories: app.categories,
          tags: app.tags);
      final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
      final file =
          await PostExporter.write('wordpress-export-$stamp.wxr', wxr);
      // Close the progress dialog no matter what happened to the
      // owning page, then show the result only if the page is alive.
      if (dialogOpen) navigator.pop();
      if (context.mounted) {
        showExportedPath(context, file.path,
            detail: '${posts.length} posts');
      }
    } catch (e) {
      if (dialogOpen) navigator.pop();
      if (context.mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.operationFailed('$e'))));
      }
    }
  }
}

class _BlogSwitcher extends StatelessWidget {
  const _BlogSwitcher({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final account = app.currentAccount!;
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        // Show quick switcher.
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...app.accounts.map((a) => ListTile(
                      leading: CircleAvatar(
                          child: Text(
                              a.name.isEmpty ? '?' : a.name[0].toUpperCase())),
                      title: Text(a.name),
                      subtitle: Text(a.homepageUrl),
                      trailing: a.id == account.id
                          ? const Icon(Icons.check_circle)
                          : null,
                      onTap: () {
                        app.selectAccount(a);
                        Navigator.of(context).pop();
                      },
                    )),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l10n.addAnotherBlog),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            const AddAccountPage(embedded: false)));
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  protocolLabel(l10n, account.protocol),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

/// A locally stored draft (offline writing) or an offline copy of a
/// server post. Tapping opens it in the editor; long-press offers
/// management (sync/delete for copies, delete for plain drafts).
class _LocalDraftTile extends StatelessWidget {
  const _LocalDraftTile({required this.draft, required this.app});

  final LocalDraft draft;
  final AppState app;

  void _openEditor(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => PostEditorPage(localDraft: draft)),
      );

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(draft.isOfflineCopy
            ? l10n.deleteLocalCopy
            : l10n.deleteDraftTitle),
        content: Text(l10n.deleteDraftConfirm(
            draft.title.isEmpty ? l10n.untitled : draft.title)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.delete)),
        ],
      ),
    );
    if (ok == true) app.deleteLocalDraft(draft.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateFmt = DateFormat.yMMMd().add_jm();
    return ListTile(
      leading: Icon(draft.isOfflineCopy
          ? Icons.cloud_done_outlined
          : Icons.cloud_off_outlined),
      title: Text(
        draft.title.trim().isEmpty ? l10n.untitled : draft.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(draft.isOfflineCopy
          ? l10n.offlineCopySubtitle(dateFmt.format(draft.updatedAt))
          : l10n.localDraftSubtitle(dateFmt.format(draft.updatedAt))),
      onTap: () => _openEditor(context),
      onLongPress: () => draft.isOfflineCopy
          ? _showCopyActions(context)
          : _confirmDelete(context),
    );
  }

  /// Offline-copy management sheet: open, push changes to the server,
  /// or remove the local copy.
  void _showCopyActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                draft.title.isEmpty ? l10n.untitled : draft.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.editPost),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openEditor(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text(l10n.syncNow),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _sync(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text(l10n.deleteLocalCopy,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sync(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await app.syncOfflineCopy(draft);
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(ok ? l10n.syncedToBlog : l10n.operationFailed(''))));
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.operationFailed('$e'))));
      }
    }
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.app});

  final BlogPost post;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateFmt = DateFormat.yMMMd().add_jm();
    final categoryNames =
        post.categories.map(app.categoryName).take(3).join(', ');

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Row(
        children: [
          Expanded(
            child: Text(
              post.title.isEmpty ? l10n.untitled : post.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(status: post.status),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.displayExcerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (post.datePublished != null)
                  dateFmt.format(post.datePublished!.toLocal()),
                if (categoryNames.isNotEmpty) categoryNames,
                if (post.isPage) l10n.page,
              ].join(' • '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      isThreeLine: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostEditorPage(existingPost: post),
        ),
      ),
      onLongPress: () => _showActions(context, post),
    );
  }

  /// Long-press management sheet: quick status transitions and delete,
  /// all backed by the same editPost/deletePost calls the editor uses.
  void _showActions(BuildContext context, BlogPost post) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                post.title.isEmpty ? l10n.untitled : post.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.editPost),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PostEditorPage(existingPost: post),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: Text(l10n.saveOfflineCopy),
              subtitle: Text(l10n.saveOfflineCopyHelp),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _saveOffline(context, post);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(l10n.exportPost),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _exportPost(context, post);
              },
            ),
            if (post.status != PostStatus.publish)
              ListTile(
                leading: const Icon(Icons.publish_outlined),
                title: Text(l10n.publish),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _changeStatus(context, post, PostStatus.publish);
                },
              ),
            if (post.status != PostStatus.draft)
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: Text(l10n.moveToDraft),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _changeStatus(context, post, PostStatus.draft);
                },
              ),
            if (post.status != PostStatus.private)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.setAsPrivate),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _changeStatus(context, post, PostStatus.private);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text(l10n.moveToTrash,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deletePost(context, post);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeStatus(
      BuildContext context, BlogPost post, PostStatus target) async {
    final l10n = AppLocalizations.of(context)!;
    final svc = app.service;
    if (svc == null) return;
    post.status = target;
    try {
      // editPost(publish: false) always saves as draft — exactly what a
      // "move to draft" needs; other targets ride the publish path.
      await svc.editPost(post, publish: target != PostStatus.draft);
      await app.refresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.operationFailed('$e'))));
      }
    }
  }

  /// Downloads the full post and stores it as an offline copy.
  Future<void> _saveOffline(BuildContext context, BlogPost post) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final svc = app.service;
    if (svc == null || post.id == null) return;
    try {
      final full = await svc.getPost(post.id!, isPage: post.isPage);
      await app.saveOfflinePost(full);
      if (context.mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.savedOfflineCopy)));
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.operationFailed('$e'))));
      }
    }
  }

  /// Single-post export: HTML or Markdown, saved to the local file
  /// system. Fetches the full post first — list entries can be partial.
  Future<void> _exportPost(BuildContext context, BlogPost post) async {
    final l10n = AppLocalizations.of(context)!;
    final svc = app.service;
    if (svc == null || post.id == null) return;
    BlogPost full = post;
    try {
      full = await svc.getPost(post.id!, isPage: post.isPage);
    } catch (_) {
      // Offline: fall back to whatever the list provided.
    }
    if (!context.mounted) return;
    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.exportPost),
        content: Text(l10n.exportFormatHint),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.of(context).pop('md'),
              child: Text(l10n.markdownFormat)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop('html'),
              child: Text(l10n.htmlFormat)),
        ],
      ),
    );
    if (format == null || !context.mounted) return;
    try {
      final contents = format == 'md'
          ? PostExporter.toMarkdown(full, categoryName: app.categoryName)
          : PostExporter.buildHtmlDocument(full);
      final file = await PostExporter.write(
          PostExporter.postFileName(full, format), contents);
      if (context.mounted) showExportedPath(context, file.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.operationFailed('$e'))));
      }
    }
  }

  Future<void> _deletePost(BuildContext context, BlogPost post) async {
    final l10n = AppLocalizations.of(context)!;
    final svc = app.service;
    if (svc == null || post.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.moveToTrash),
        content: Text(l10n
            .deletePostConfirm(post.title.isEmpty ? l10n.untitled : post.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.moveToTrash),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await svc.deletePost(post.id!, isPage: post.isPage);
      await app.refresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.operationFailed('$e'))));
      }
    }
  }
}

/// Export-success dialog: shows where the file was written and offers
/// the system share sheet (AirDrop/WeChat/Mail…) so the file can be
/// sent to other people directly.
void showExportedPath(BuildContext context, String path, {String? detail}) {
  final l10n = AppLocalizations.of(context)!;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.exportDoneTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(path),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail,
                style: TextStyle(
                    fontSize: 13, color: Theme.of(context).hintColor)),
          ],
          if (Platform.isIOS) ...[
            const SizedBox(height: 8),
            Text(l10n.exportLocationHintIOS,
                style: TextStyle(
                    fontSize: 13, color: Theme.of(context).hintColor)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok)),
        FilledButton.icon(
          icon: const Icon(Icons.ios_share, size: 18),
          label: Text(l10n.shareFile),
          onPressed: () {
            Navigator.of(context).pop();
            SharePlus.instance.share(
              ShareParams(
                files: [XFile(path)],
                previewThumbnail: null,
              ),
            );
          },
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PostStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = switch (status) {
      PostStatus.publish => Colors.green,
      PostStatus.draft => Colors.orange,
      PostStatus.pending => Colors.amber,
      PostStatus.private => Colors.purple,
      PostStatus.scheduled => Colors.blue,
      PostStatus.trash => Colors.grey,
    };
    final label = statusLabel(l10n, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.withValues(alpha: 1),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
