import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/blog.dart';
import '../models/blog_post.dart';
import '../state/app_state.dart';
import '../state/editor_state.dart';
import 'editor/editor_toolbar.dart';
import 'editor/live_preview.dart';

/// App version stamped into the copy-diagnostics report so user-submitted
/// diagnostics always identify which build they came from.
const String kAppVersion = 'v1.4.6';

/// Localized display label for a [PostStatus] (dashboard chips + editor).
String statusLabel(AppLocalizations l10n, PostStatus status) =>
    switch (status) {
      PostStatus.draft => l10n.postStatusDraft,
      PostStatus.pending => l10n.postStatusPending,
      PostStatus.private => l10n.postStatusPrivate,
      PostStatus.publish => l10n.postStatusPublish,
      PostStatus.scheduled => l10n.postStatusScheduled,
      PostStatus.trash => l10n.postStatusTrash,
    };

/// Post editor with real-time preview. Layout adapts to screen width:
/// split view (editor + preview) on desktop, tabs on phones.
class PostEditorPage extends StatefulWidget {
  const PostEditorPage({super.key, this.existingPost});

  final BlogPost? existingPost;

  @override
  State<PostEditorPage> createState() => _PostEditorPageState();
}

class _PostEditorPageState extends State<PostEditorPage>
    with SingleTickerProviderStateMixin {
  late final EditorState _editor;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagController;
  // The narrow-screen tab bar NEEDS an explicit controller: without one the
  // TabBar build fails (assertion in debug, null-controller crash subtree in
  // release) and the whole editor pane goes blank on phones.
  late final TabController _tabController =
      TabController(length: 2, vsync: this);
  int _tabIndex = 0; // 0: write, 1: preview (narrow screens)

  /// Full-content fetch state when opening an existing post.
  /// Non-blocking: the editor renders immediately with whatever the post
  /// list provided; the fresh copy replaces it in the background.
  bool _fetchingFull = false;
  String? _loadError;
  bool _emptyContent = false;

  /// Diagnostics captured while loading, surfaced by the "copy
  /// diagnostics" action when content comes back empty.
  String _diagListInfo = '';
  String _diagFetchInfo = '';

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _editor = EditorState(
      service: app.service,
      initialPost: widget.existingPost?.copy(),
      theme: app.theme,
    );
    _titleController = TextEditingController(text: widget.existingPost?.title ?? '');
    _contentController =
        TextEditingController(text: widget.existingPost?.content ?? '');
    _tagController =
        TextEditingController(text: widget.existingPost?.tags.join(', ') ?? '');
    // The empty-content notice is only meaningful for EXISTING posts whose
    // content failed to load — never for a brand-new blank post.
    _emptyContent = widget.existingPost != null &&
        widget.existingPost!.content.trim().isEmpty;
    final existing = widget.existingPost;
    if (existing != null) {
      _diagListInfo =
          '列表项: id=${existing.id ?? "?"}, 标题=${existing.title.length}字, '
          '正文=${existing.content.length}字, 摘要=${existing.excerpt.length}字, '
          '状态=${existing.status.wpValue}';
    }

    // Post lists often ship without full content — fetch the complete
    // post in the background. The editor stays interactive the whole time.
    if (existing != null && !existing.isNew && app.service != null) {
      _fetchingFull = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFullPost());
    }
  }

  Future<void> _loadFullPost() async {
    final app = context.read<AppState>();
    final svc = app.service;
    final existing = widget.existingPost;
    // The caller only arms this when both are present; guard anyway and
    // ALWAYS clear the fetching flag — a stuck spinner used to leave the
    // whole editor (title included) invisible and uneditable.
    if (svc == null || existing == null) {
      if (mounted) setState(() => _fetchingFull = false);
      return;
    }
    try {
      final fresh = await svc
          .getPost(existing.id!, isPage: existing.isPage)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _diagFetchInfo =
          '全文接口: 成功, 标题=${fresh.title.length}字, 正文=${fresh.content.length}字, '
          '摘要=${fresh.excerpt.length}字, 标签=${fresh.tags.length}个';
      setState(() {
        _fetchingFull = false;
        _loadError = null;
        _editor.applyPost(fresh);
        if (fresh.title.trim().isNotEmpty) {
          _titleController.text = fresh.title;
        }
        if (fresh.content.trim().isNotEmpty) {
          _emptyContent = false;
          // Keep the caret at the end after replacing the text.
          _contentController.value = TextEditingValue(
            text: fresh.content,
            selection: TextSelection.collapsed(
                offset: fresh.content.length),
          );
        } else {
          // Distinguish "failed to load" from "server returned empty body".
          _emptyContent = _contentController.text.trim().isEmpty;
        }
        if (fresh.tags.isNotEmpty) {
          _tagController.text = fresh.tags.join(', ');
        }
      });
    } catch (e) {
      if (!mounted) return;
      _diagFetchInfo = '全文接口: 失败 ($e)';
      // Degrade gracefully: keep whatever the post list gave us.
      setState(() {
        _fetchingFull = false;
        _loadError = '$e';
      });
    }
  }

  /// Copies a diagnostic report (protocol, account, field lengths and the
  /// raw server payload) so empty-content issues can be pinpointed from
  /// the user's device without a debugger.
  Future<void> _copyDiagnostics(AppState app) async {
    final account = app.currentAccount;
    final svc = app.service;
    final buf = StringBuffer()
      ..writeln('== Open Live Writer 诊断 ==')
      ..writeln('版本: $kAppVersion')
      ..writeln('当前页面: ${widget.existingPost == null ? "新建文章" : "文章 id=${widget.existingPost!.id}"}')
      ..writeln('协议: ${account?.protocol.name ?? "?"}'
          '${account?.protocol == BlogProtocol.rest ? " (${account?.restAuth.name})" : " (${account?.flavor.name})"}')
      ..writeln('站点: ${account?.homepageUrl ?? "?"}')
      ..writeln('接口: ${account?.apiUrl ?? "?"}')
      ..writeln('用户: ${account?.username ?? "?"}')
      ..writeln('最近文章加载: ${svc?.lastGetPostDiag ?? "(本会话未调用)"}')
      ..writeln(_diagListInfo)
      ..writeln(_diagFetchInfo)
      ..writeln('编辑器实际文本: 标题=${_titleController.text.length}字, '
          '正文=${_contentController.text.length}字')
      ..writeln('UI 状态: fetching=$_fetchingFull, empty=$_emptyContent, '
          'error=${_loadError == null ? "无" : "有"}')
      ..writeln('-- 原始响应 --')
      ..writeln(svc?.lastResponseBody ?? '(无)');
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.diagnosticsCopied)));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _editor.dispose();
    super.dispose();
  }

  Future<void> _save({required bool publish}) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await _editor.save(publish: publish);
    if (!mounted) return;
    showEditorSnack(
      context,
      ok
          ? (publish
              ? l10n.postPublished(_editor.lastSavedId != null
                  ? ' (id ${_editor.lastSavedId})'
                  : '')
              : l10n.draftSaved)
          : (_editor.saveError ?? l10n.saveFailed),
    );
    // Reload the home post list so the saved post shows up immediately.
    if (ok) {
      context.read<AppState>().refresh();
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_editor.isDirty) return true;
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardChanges),
        content: Text(l10n.discardConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.stay),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l10n = AppLocalizations.of(context)!;
    final isWide = MediaQuery.of(context).size.width >= 1000;

    // Listen to the editor state so applyPost()/saving changes rebuild the
    // page — without this, loaded content and the save spinner never show.
    return ListenableBuilder(
      listenable: _editor,
      builder: (context, _) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _editor.post.isNew
                      ? (_editor.post.isPage
                          ? l10n.newPageTitle
                          : l10n.newPostTitle)
                      : l10n.editTitle(_editor.post.title.isEmpty
                          ? l10n.untitled
                          : _editor.post.title),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_fetchingFull) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          actions: [
            if (_editor.saving)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              // Icon + tooltip instead of a text label: four text-labeled
              // actions overflow the AppBar on phone widths.
              IconButton(
                tooltip: l10n.saveDraft,
                icon: const Icon(Icons.save_outlined),
                onPressed: () => _save(publish: false),
              ),
              FilledButton(
                onPressed: () => _save(publish: true),
                child: Text(l10n.publish),
              ),
            ],
            IconButton(
              tooltip: l10n.postSettings,
              icon: const Icon(Icons.tune),
              onPressed: () => _openSettingsSheet(context, app),
            ),
            PopupMenuButton<String>(
              tooltip: l10n.copyDiagnostics,
              icon: const Icon(Icons.bug_report_outlined),
              onSelected: (value) {
                if (value == 'diag') _copyDiagnostics(app);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'diag',
                  child: Text(l10n.copyDiagnostics),
                ),
              ],
            ),
          ],
        ),
        // Non-blocking body: the editor renders immediately with the list
        // data; the fresh full-content copy arrives in the background. A
        // full-screen spinner here used to make the whole editor (title
        // included) invisible and uneditable whenever the fetch stalled.
        body: Column(
          children: [
            if (_emptyContent && !_fetchingFull)
              MaterialBanner(
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                content: Text(
                  l10n.emptyContentNotice,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSecondaryContainer,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => _copyDiagnostics(app),
                    child: Text(l10n.copyDiagnostics),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _emptyContent = false),
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            if (_loadError != null)
              MaterialBanner(
                backgroundColor:
                    Theme.of(context).colorScheme.errorContainer,
                content: Text(
                  AppLocalizations.of(context)!
                      .loadPostFailed(_loadError!),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _loadError = null;
                        _fetchingFull = true;
                      });
                      _loadFullPost();
                    },
                    child: Text(AppLocalizations.of(context)!.retry),
                  ),
                  TextButton(
                    onPressed: () => _copyDiagnostics(app),
                    child: Text(l10n.copyDiagnostics),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _loadError = null),
                    child: Text(AppLocalizations.of(context)!.cancel),
                  ),
                ],
              ),
            Expanded(
              child: isWide ? _buildSplitView(app) : _buildTabbedView(app),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildSplitView(AppState app) {
    return Row(
      children: [
        Expanded(child: _buildEditorPane(app)),
        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
        Expanded(
          child: LivePreview(
            content: _editor.post.content,
            title: _titleController.text,
            theme: _editor.theme,
            onContentChanged: _editor.contentChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildTabbedView(AppState app) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          onTap: (i) => setState(() => _tabIndex = i),
          tabs: [
            Tab(icon: const Icon(Icons.edit), text: l10n.write),
            Tab(icon: const Icon(Icons.visibility), text: l10n.preview),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _buildEditorPane(app),
              LivePreview(
                content: _editor.post.content,
                title: _titleController.text,
                theme: _editor.theme,
                onContentChanged: _editor.contentChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditorPane(AppState app) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _titleController,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: l10n.postTitle,
            ),
            onChanged: _editor.updateTitle,
          ),
        ),
        const Divider(height: 1),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: EditorToolbar(
            controller: _contentController,
            onContentChanged: _editor.updateContent,
            uploadMedia: (filename, bytes, mime) {
              final svc = context.read<AppState>().service;
              if (svc == null) {
                throw StateError('No blog connection');
              }
              return svc.uploadMedia(filename, bytes, mime);
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _contentController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              // Custom font families ('monospace', 'Courier New') failed to
              // resolve on iOS and rendered every glyph blank. Derive the
              // style from the theme (same resolution path as the title
              // field, which is proven to render).
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontSize: 14, height: 1.6),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: l10n.writePostHint,
              ),
              onChanged: _editor.updateContent,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSettingsSheet(BuildContext context, AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, scrollController) => _PostSettingsSheet(
          editor: _editor,
          app: app,
          tagController: _tagController,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

/// Post settings: status, schedule, categories, tags, excerpt, slug,
/// discussion flags — the Flutter counterpart of OLW's sidebar.
class _PostSettingsSheet extends StatelessWidget {
  const _PostSettingsSheet({
    required this.editor,
    required this.app,
    required this.tagController,
    required this.scrollController,
  });

  final EditorState editor;
  final AppState app;
  final TextEditingController tagController;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(l10n.postSettings,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),

          // --- Status ------------------------------------------------------
          DropdownButtonFormField<PostStatus>(
            value: editor.post.status,
            decoration: InputDecoration(
                labelText: l10n.statusApplied),
            items: PostStatus.values
                .map((s) =>
                    DropdownMenuItem(value: s, child: Text(statusLabel(l10n, s))))
                .toList(),
            onChanged: (v) => editor.updateStatus(v!),
          ),
          const SizedBox(height: 16),

          // --- Schedule ----------------------------------------------------
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.publishDate),
            subtitle: Text(editor.post.datePublished == null
                ? l10n.immediately
                : '${editor.post.datePublished!.toLocal()}'),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: editor.post.datePublished ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null || !context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime:
                    TimeOfDay.fromDateTime(editor.post.datePublished ?? DateTime.now()),
              );
              if (time == null) return;
              editor.setPublishDate(DateTime(
                picked.year,
                picked.month,
                picked.day,
                time.hour,
                time.minute,
              ));
            },
          ),

          // --- Categories --------------------------------------------------
          if (app.categories.isNotEmpty) ...[
            Text(l10n.categories,
                style: Theme.of(context).textTheme.titleSmall),
            ...app.categories.map(
              (cat) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: editor.post.categories.contains(cat.id),
                title: Text(cat.name),
                onChanged: (_) => editor.toggleCategory(cat.id),
              ),
            ),
            const SizedBox(height: 8),
          ] else if (editor.post.categories.isNotEmpty) ...[
            Text(l10n.categories, style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: editor.post.categories
                  .map((c) => Chip(label: Text(app.categoryName(c))))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],

          // --- Tags --------------------------------------------------------
          TextField(
            controller: tagController,
            decoration: InputDecoration(
              labelText: l10n.tagsLabel,
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                tooltip: l10n.applyTags,
                onPressed: () => editor.setTags(
                  tagController.text
                      .split(',')
                      .map((t) => t.trim())
                      .where((t) => t.isNotEmpty)
                      .toList(),
                ),
              ),
            ),
            onSubmitted: (value) => editor.setTags(
              value.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
            ),
          ),
          if (app.tagNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: app.tagNames
                    .take(15)
                    .map((name) => ActionChip(
                          label: Text(name),
                          onPressed: () {
                            final tags = List.of(editor.post.tags);
                            if (!tags.contains(name)) tags.add(name);
                            editor.setTags(tags);
                            tagController.text = tags.join(', ');
                          },
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 16),

          // --- Excerpt & slug ----------------------------------------------
          TextField(
            controller: TextEditingController(text: editor.post.excerpt)
              ..selection = TextSelection.fromPosition(
                  TextPosition(offset: editor.post.excerpt.length)),
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.excerpt,
              alignLabelWithHint: true,
            ),
            onChanged: editor.updateExcerpt,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: TextEditingController(text: editor.post.slug ?? '')
              ..selection = TextSelection.fromPosition(
                  TextPosition(offset: (editor.post.slug ?? '').length)),
            decoration: InputDecoration(
              labelText: l10n.urlSlug,
              prefixText: '/?',
            ),
            onChanged: editor.updateSlug,
          ),
          const SizedBox(height: 16),

          // --- Discussion --------------------------------------------------
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.allowComments),
            value: editor.post.commentsEnabled,
            onChanged: editor.setCommentsEnabled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.allowPingbacks),
            value: editor.post.pingsEnabled,
            onChanged: editor.setPingsEnabled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.treatAsPage),
            value: editor.post.isPage,
            onChanged: editor.setIsPage,
          ),
        ],
      ),
    );
  }
}
