import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/blog_post.dart';
import '../state/app_state.dart';
import '../state/editor_state.dart';
import 'editor/editor_toolbar.dart';
import 'editor/live_preview.dart';

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

class _PostEditorPageState extends State<PostEditorPage> {
  late final EditorState _editor;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagController;
  int _tabIndex = 0; // 0: write, 1: preview (narrow screens)

  /// Full-content fetch state when opening an existing post.
  bool _loadingFull = false;
  String? _loadError;

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

    // Post lists often ship without full content — fetch the complete
    // post from the service (this mirrors OLW opening a post).
    final existing = widget.existingPost;
    if (existing != null && !existing.isNew && app.service != null) {
      _loadingFull = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFullPost());
    }
  }

  Future<void> _loadFullPost() async {
    final app = context.read<AppState>();
    final svc = app.service;
    final existing = widget.existingPost;
    if (svc == null || existing == null) return;
    try {
      final fresh = await svc.getPost(existing.id!, isPage: existing.isPage);
      if (!mounted) return;
      setState(() {
        _loadingFull = false;
        _loadError = null;
        _editor.applyPost(fresh);
        if (fresh.title.trim().isNotEmpty) {
          _titleController.text = fresh.title;
        }
        if (fresh.content.trim().isNotEmpty) {
          _contentController.text = fresh.content;
        }
        if (fresh.tags.isNotEmpty) {
          _tagController.text = fresh.tags.join(', ');
        }
      });
    } catch (e) {
      if (!mounted) return;
      // Degrade gracefully: keep whatever the post list gave us.
      setState(() {
        _loadingFull = false;
        _loadError = '$e';
      });
    }
  }

  @override
  void dispose() {
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _editor.post.isNew
                ? (_editor.post.isPage ? l10n.newPageTitle : l10n.newPostTitle)
                : l10n.editTitle(_editor.post.title.isEmpty
                    ? l10n.untitled
                    : _editor.post.title),
            overflow: TextOverflow.ellipsis,
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
              TextButton(
                onPressed: () => _save(publish: false),
                child: Text(l10n.saveDraft),
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
          ],
        ),
        body: _loadingFull
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
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
                            setState(() => _loadError = null);
                            _loadFullPost();
                          },
                          child: Text(AppLocalizations.of(context)!.retry),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _loadError = null),
                          child: Text(AppLocalizations.of(context)!.cancel),
                        ),
                      ],
                    ),
                  Expanded(
                    child: isWide
                        ? _buildSplitView(app)
                        : _buildTabbedView(app),
                  ),
                ],
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
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.6,
              ),
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
