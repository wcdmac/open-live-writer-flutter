import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../editor/block_editor.dart';
import '../l10n/app_localizations.dart';
import '../models/blog_post.dart';
import '../services/local_draft_store.dart';
import '../state/app_state.dart';
import '../state/editor_state.dart';
import 'editor/editor_toolbar.dart';
import 'editor/live_preview.dart';

/// App version.
const String kAppVersion = 'v1.7.4';

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
  const PostEditorPage({super.key, this.existingPost, this.localDraft});

  final BlogPost? existingPost;

  /// Opens the editor pre-filled from a locally stored draft (offline
  /// writing). On the first successful save to the blog the local draft
  /// is removed automatically.
  final LocalDraft? localDraft;

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
      TabController(length: 3, vsync: this);
  int _tabIndex = 0; // 0: visual, 1: source, 2: preview (narrow screens)

  /// Wide layout: which editor mode the left pane shows (visual / source).
  int _wideEditorMode = 0;

  /// Full-content fetch state when opening an existing post.
  /// Non-blocking: the editor renders immediately with whatever the post
  /// list provided; the fresh copy replaces it in the background.
  bool _fetchingFull = false;
  String? _loadError;
  bool _emptyContent = false;

  // --- Undo / redo + word count ------------------------------------------
  // Page-level snapshot history covering title + content. The visual editor
  // picks external controller changes up via its didUpdateWidget, so one
  // stack covers both editing modes.
  final List<(String, String)> _undoStack = [];
  final List<(String, String)> _redoStack = [];
  bool _applyingHistory = false;
  Timer? _historyDebounce;
  int _charCount = 0;

  /// Id of the local draft this editor session was opened from (null when
  /// not editing a local draft). Consumed after the first successful save.
  String? _sourceDraftId;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final draft = widget.localDraft;
    _editor = EditorState(
      service: app.service,
      // An offline copy carries its server post id: opening it must edit
      // that post (editPost), not publish a duplicate (newPost).
      initialPost: widget.existingPost?.copy() ??
          (draft != null && draft.isOfflineCopy ? draft.toBlogPost() : null),
      theme: app.theme,
    );
    _titleController = TextEditingController(
        text: widget.existingPost?.title ?? draft?.title ?? '');
    _contentController = TextEditingController(
        text: widget.existingPost?.content ?? draft?.content ?? '');
    // Show tag NAMES: REST posts carry numeric ids; tagName() maps them
    // back (falling back to the raw value, which also covers XML-RPC
    // name-style tags).
    String? initialTags;
    if (widget.existingPost != null) {
      initialTags =
          widget.existingPost!.tags.map(app.tagName).join(', ');
    } else if (draft != null) {
      initialTags = draft.tags.map(app.tagName).join(', ');
    }
    _tagController = TextEditingController(text: initialTags ?? '');
    if (draft != null) {
      if (!draft.isOfflineCopy) {
        _editor.updateTitle(draft.title);
        _editor.updateContent(draft.content);
        if (draft.excerpt.isNotEmpty) _editor.updateExcerpt(draft.excerpt);
        if (draft.slug?.isNotEmpty == true) _editor.updateSlug(draft.slug!);
      }
      _sourceDraftId = draft.id;
    }
    // Baseline snapshot: undo can never go past the state the page opened
    // with.
    _undoStack.add((_titleController.text, _contentController.text));
    _titleController.addListener(_onHistorySourceChanged);
    _contentController.addListener(_onHistorySourceChanged);
    _updateCharCount();
    // The empty-content notice is only meaningful for EXISTING posts whose
    // content failed to load — never for a brand-new blank post.
    _emptyContent = widget.existingPost != null &&
        widget.existingPost!.content.trim().isEmpty;

    // Crash recovery: a NEW post (not opened from a local draft) checks for
    // an unsaved snapshot from a previous session.
    if (widget.existingPost == null && draft == null && app.hasAccount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkCrashSnapshot(app));
    }

    // Post lists often ship without full content — fetch the complete
    // post in the background. The editor stays interactive the whole time.
    final existing = widget.existingPost;
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
      // The editor is interactive while this fetch runs; silently
      // overwriting what the user already typed would eat their work.
      if (_editor.isDirty) {
        setState(() => _fetchingFull = false);
        return;
      }
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
          _tagController.text =
              fresh.tags.map(app.tagName).join(', ');
        }
        // Fresh server copy = new baseline; user edits start from here.
        _applyingHistory = true;
        _undoStack
          ..clear()
          ..add((_titleController.text, _contentController.text));
        _redoStack.clear();
        _applyingHistory = false;
        _updateCharCount();
      });
    } catch (e) {
      if (!mounted) return;
      // Degrade gracefully: keep whatever the post list gave us.
      setState(() {
        _fetchingFull = false;
        _loadError = '$e';
      });
    }
  }

  @override
  void dispose() {
    _historyDebounce?.cancel();
    _tabController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _editor.dispose();
    super.dispose();
  }

  // --- Undo / redo + word count -------------------------------------------

  /// Debounced snapshot capture on every title/content change.
  void _onHistorySourceChanged() {
    if (_applyingHistory) return;
    _updateCharCount();
    _historyDebounce?.cancel();
    _historyDebounce = Timer(const Duration(milliseconds: 700), _pushHistory);
  }

  void _pushHistory() {
    if (_applyingHistory || !mounted) return;
    final snap = (_titleController.text, _contentController.text);
    final last = _undoStack.lastOrNull;
    if (last != null && last.$1 == snap.$1 && last.$2 == snap.$2) return;
    _undoStack.add(snap);
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
    setState(() {});
    // Crash-recovery autosave: a NEW post's in-progress work is mirrored
    // to the per-account snapshot slot after every committed edit batch.
    if (widget.existingPost == null &&
        (snap.$1.trim().isNotEmpty || snap.$2.trim().isNotEmpty)) {
      final app = context.read<AppState>();
      final account = app.currentAccount;
      if (account != null) {
        app.drafts.saveSnapshot(
          account.id,
          CrashSnapshot(
            title: snap.$1,
            content: snap.$2,
            savedAt: DateTime.now(),
          ),
        );
      }
    }
  }

  void _undo() {
    if (_undoStack.length < 2 || _applyingHistory) return;
    _applyHistory(_undoStack.removeLast(), _redoStack);
  }

  void _redo() {
    if (_redoStack.isEmpty || _applyingHistory) return;
    _applyHistory(_redoStack.removeLast(), _undoStack);
  }

  void _applyHistory((String, String) target, List<(String, String)> other) {
    setState(() {
      _applyingHistory = true;
      other.add((_titleController.text, _contentController.text));
      _titleController.value = TextEditingValue(
        text: target.$1,
        selection: TextSelection.collapsed(offset: target.$1.length),
      );
      _contentController.value = TextEditingValue(
        text: target.$2,
        selection: TextSelection.collapsed(offset: target.$2.length),
      );
      _editor.updateTitle(target.$1);
      _editor.updateContent(target.$2);
      _applyingHistory = false;
      _updateCharCount();
    });
  }

  /// Counts visible characters (tags, WP block comments and whitespace
  /// stripped). For CJK text this is the conventional "字数".
  void _updateCharCount() {
    final text =
        (_titleController.text + _contentController.text)
            .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\s'), '');
    final n = text.runes.length;
    if (n != _charCount) {
      _charCount = n;
      if (mounted) setState(() {});
    }
  }

  /// Compact bar under the AppBar: undo / redo + live word count.
  Widget _buildHistoryBar() {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: l10n.undo,
              icon: const Icon(Icons.undo, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: _undoStack.length >= 2 ? _undo : null,
            ),
            IconButton(
              tooltip: l10n.redo,
              icon: const Icon(Icons.redo, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: _redoStack.isNotEmpty ? _redo : null,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                l10n.charCount(_charCount),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save({required bool publish}) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await _editor.save(publish: publish);
    if (!mounted) return;
    final app = context.read<AppState>();
    if (ok) {
      showEditorSnack(
        context,
        publish
            ? l10n.postPublished(_editor.lastSavedId != null
                ? ' (id ${_editor.lastSavedId})'
                : '')
            : l10n.draftSaved,
      );
      final account = app.currentAccount;
      if (account != null) {
        // The draft made it to the server: crash snapshot and source
        // local draft are both obsolete. An offline COPY stays around —
        // refreshed from what was just pushed — so it remains available
        // for the next offline session.
        app.drafts.clearSnapshot(account.id);
        if (_sourceDraftId != null) {
          final source = app.localDrafts
              .where((d) => d.id == _sourceDraftId)
              .firstOrNull;
          if (source != null && source.isOfflineCopy) {
            await app.saveOfflinePost(_editor.post);
          } else {
            await app.deleteLocalDraft(_sourceDraftId!);
          }
          _sourceDraftId = null;
        }
      }
      unawaited(app.refresh()); // Intentionally fire-and-forget.
    } else if (_isNetworkError(_editor.saveError)) {
      // Offline fallback: park the draft locally so nothing is lost; the
      // home screen lists it under local drafts for later publishing.
      await _saveLocalDraft(app);
      if (mounted) showEditorSnack(context, l10n.savedOfflineDraft);
    } else {
      showEditorSnack(context, _editor.saveError ?? l10n.saveFailed);
    }
  }

  /// True when the save error looks like a connectivity failure rather
  /// than a server rejection.
  bool _isNetworkError(String? message) => message != null &&
      RegExp(
          r'SocketException|TimeoutException|Connection|Failed host lookup|ClientException|Transport error|Network is unreachable',
          caseSensitive: false).hasMatch(message);

  /// Saves the current editor content as a local (offline) draft.
  /// Offline-copy metadata (server post id, status, taxonomy) rides
  /// along so a parked copy still syncs back with editPost later.
  Future<void> _saveLocalDraft(AppState app) async {
    final account = app.currentAccount;
    if (account == null) return;
    final source = _sourceDraftId == null
        ? null
        : app.localDrafts.where((d) => d.id == _sourceDraftId).firstOrNull;
    await app.saveLocalDraft(LocalDraft(
      id: _sourceDraftId ?? app.newDraftId(),
      accountId: account.id,
      title: _titleController.text,
      content: _contentController.text,
      excerpt: _editor.post.excerpt,
      slug: _editor.post.slug,
      updatedAt: DateTime.now(),
      postId: source?.postId,
      postStatus: source?.postStatus ?? _editor.post.status.wpValue,
      isPage: source?.isPage ?? _editor.post.isPage,
      categories: source?.categories,
      tags: source?.tags,
    ));
    _sourceDraftId ??= app.localDrafts
        .where((d) => d.accountId == account.id &&
            d.title == _titleController.text &&
            d.content == _contentController.text)
        .firstOrNull
        ?.id;
  }

  /// Offers to restore the crash snapshot left by a previous new-post
  /// session (app kill, crash, forced quit).
  Future<void> _checkCrashSnapshot(AppState app) async {
    final account = app.currentAccount;
    if (account == null || !mounted) return;
    final snap = await app.drafts.loadSnapshot(account.id);
    if (snap == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.crashRecoveryTitle),
        content: Text(l10n.crashRecoveryBody(
            snap.savedAt.toLocal().toString().substring(0, 16))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.discard),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (restore == true) {
      setState(() {
        _applyingHistory = true;
        _titleController.text = snap.title;
        _contentController.value = TextEditingValue(
          text: snap.content,
          selection: TextSelection.collapsed(offset: snap.content.length),
        );
        _editor.updateTitle(snap.title);
        _editor.updateContent(snap.content);
        _applyingHistory = false;
        _undoStack
          ..clear()
          ..add((_titleController.text, _contentController.text));
        _redoStack.clear();
        _updateCharCount();
      });
    } else {
      app.drafts.clearSnapshot(account.id);
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
                    onPressed: () =>
                        setState(() => _loadError = null),
                    child: Text(AppLocalizations.of(context)!.cancel),
                  ),
                ],
              ),
            _buildHistoryBar(),
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
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              // Visual / source mode switch for the desktop split layout.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.visibility, size: 16),
                        label: Text(l10n.visualMode)),
                    ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.code, size: 16),
                        label: Text(l10n.sourceMode)),
                  ],
                  selected: {_wideEditorMode},
                  onSelectionChanged: (s) =>
                      setState(() => _wideEditorMode = s.first),
                ),
              ),
              Expanded(
                child: _wideEditorMode == 0
                    ? _buildVisualPane(app)
                    : _buildEditorPane(app),
              ),
            ],
          ),
        ),
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
            Tab(icon: const Icon(Icons.visibility), text: l10n.visualMode),
            Tab(icon: const Icon(Icons.code), text: l10n.sourceMode),
            Tab(icon: const Icon(Icons.preview), text: l10n.preview),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _buildVisualPane(app),
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

  /// Visual (WYSIWYG) block editor pane. Edits flow back into the shared
  /// content controller + editor state so source mode and preview stay in
  /// sync; external content loads are picked up via BlockEditor's
  /// didUpdateWidget.
  Widget _buildVisualPane(AppState app) {
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
        Expanded(
          child: BlockEditor(
            content: _contentController.text,
            onContentChanged: (html) {
              // Programmatic controller update — doesn't re-trigger onChanged.
              _contentController.value = TextEditingValue(
                text: html,
                selection: TextSelection.collapsed(offset: html.length),
              );
              _editor.updateContent(html);
            },
            uploadMedia: (filename, bytes, mime) {
              final svc = app.service;
              if (svc == null) {
                throw StateError('No blog connection');
              }
              return svc.uploadMedia(filename, bytes, mime);
            },
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
///
/// Stateful so the excerpt/slug/password fields own persistent
/// controllers — building them inline allocated (and leaked) a new
/// TextEditingController on every rebuild of the sheet.
class _PostSettingsSheet extends StatefulWidget {
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
  State<_PostSettingsSheet> createState() => _PostSettingsSheetState();
}

class _PostSettingsSheetState extends State<_PostSettingsSheet> {
  late final TextEditingController _excerptCtrl;
  late final TextEditingController _slugCtrl;
  late final TextEditingController _passwordCtrl;

  @override
  void initState() {
    super.initState();
    _excerptCtrl = TextEditingController(text: widget.editor.post.excerpt);
    _slugCtrl =
        TextEditingController(text: widget.editor.post.slug ?? '');
    _passwordCtrl =
        TextEditingController(text: widget.editor.post.password ?? '');
  }

  @override
  void dispose() {
    _excerptCtrl.dispose();
    _slugCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final app = widget.app;
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) => ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(l10n.postSettings,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          // --- Save local draft (offline writing) -------------------------
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_off_outlined),
            title: Text(l10n.saveLocalDraft),
            subtitle: Text(l10n.saveLocalDraftHelp),
            onTap: () async {
              final account = app.currentAccount;
              if (account == null) return;
              final messenger = ScaffoldMessenger.of(context);
              if (editor.post.id != null) {
                // Existing post: store as an offline copy (keeps server
                // id so a later save edits instead of duplicating).
                await app.saveOfflinePost(editor.post);
              } else {
                await app.saveLocalDraft(LocalDraft(
                  id: app.newDraftId(),
                  accountId: account.id,
                  title: editor.post.title,
                  content: editor.post.content,
                  excerpt: editor.post.excerpt,
                  slug: editor.post.slug,
                  updatedAt: DateTime.now(),
                ));
              }
              messenger.showSnackBar(
                  SnackBar(content: Text(l10n.savedOfflineDraft)));
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),

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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.newCategory),
                onPressed: () => _createCategory(context, app, editor),
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
            controller: widget.tagController,
            decoration: InputDecoration(
              labelText: l10n.tagsLabel,
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                tooltip: l10n.applyTags,
                onPressed: () => editor.setTags(
                  widget.tagController.text
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
                            widget.tagController.text = tags.join(', ');
                          },
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 16),

          // --- Excerpt & slug ----------------------------------------------
          TextField(
            controller: _excerptCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.excerpt,
              alignLabelWithHint: true,
            ),
            onChanged: editor.updateExcerpt,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _slugCtrl,
            decoration: InputDecoration(
              labelText: l10n.urlSlug,
              prefixText: '/?',
            ),
            onChanged: editor.updateSlug,
          ),
          const SizedBox(height: 12),
          // Password protection: visitors must enter this password to read
          // the post (public + password; distinct from the private status,
          // which hides the post from everyone but the owner).
          TextField(
            controller: _passwordCtrl,
            decoration: InputDecoration(
              labelText: l10n.postPassword,
              helperText: l10n.postPasswordHelp,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            onChanged: editor.updatePassword,
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

  /// Creates a category on the blog, then pre-selects it for this post.
  Future<void> _createCategory(
      BuildContext context, AppState app, EditorState editor) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newCategory),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.newCategoryHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(l10n.ok)),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (name == null || name.isEmpty) return;
    final ok = await app.createCategory(name);
    if (!ok || !context.mounted) return;
    // Pre-select the freshly created category by name.
    final created =
        app.categories.where((c) => c.name == name).firstOrNull;
    if (created != null && !editor.post.categories.contains(created.id)) {
      editor.toggleCategory(created.id);
    }
  }
}
