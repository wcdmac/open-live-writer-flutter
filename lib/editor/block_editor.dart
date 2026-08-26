import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:image_picker/image_picker.dart' as imgpick;

import '../l10n/app_localizations.dart';
import '../views/editor/editor_toolbar.dart'
    show MediaUploader, mediaUploadErrorText;
import 'block_document.dart';
import 'video_placeholder.dart';

/// Visual (WYSIWYG) block editor.
///
/// Renders the post as a list of blocks. Blocks that are not being edited
/// show their rendered form (real WYSIWYG); tapping a block switches it to
/// an editing card. WordPress block comments ride along in [ContentBlock]
/// and survive every round-trip.
class BlockEditor extends StatefulWidget {
  const BlockEditor({
    super.key,
    required this.content,
    required this.onContentChanged,
    this.uploadMedia,
  });

  /// Current post HTML. External updates (e.g. full post loaded in the
  /// background) are picked up in [didUpdateWidget] and reparsed, unless
  /// the change originated from this editor itself.
  final String content;
  final ValueChanged<String> onContentChanged;

  /// Optional uploader (device pick → blog media library) for image blocks.
  final MediaUploader? uploadMedia;

  @override
  State<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<BlockEditor> {
  List<ContentBlock> _blocks = [];
  String _lastEmitted = '';
  int? _focusedIndex;

  @override
  void initState() {
    super.initState();
    _blocks = parseBlocks(widget.content);
    _lastEmitted = serializeBlocks(_blocks);
  }

  @override
  void didUpdateWidget(BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content.trim() != _lastEmitted.trim()) {
      setState(() {
        _blocks = parseBlocks(widget.content);
        _focusedIndex = null;
        _lastEmitted = serializeBlocks(_blocks);
      });
    }
  }

  void _emit() {
    _lastEmitted = serializeBlocks(_blocks);
    widget.onContentChanged(_lastEmitted);
  }

  void _updateHtml(int index, String html) {
    _blocks[index].html = html;
    _emit();
  }

  void _insert(ContentBlock block) {
    setState(() {
      final at = _focusedIndex == null ? _blocks.length : _focusedIndex! + 1;
      _blocks.insert(at, block);
      _focusedIndex = at;
    });
    _emit();
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _blocks.length) return;
    setState(() {
      final b = _blocks.removeAt(index);
      _blocks.insert(target, b);
      if (_focusedIndex == index) {
        _focusedIndex = target;
      } else if (_focusedIndex == target) {
        _focusedIndex = index;
      }
    });
    _emit();
  }

  void _delete(int index) {
    setState(() {
      _blocks.removeAt(index);
      if (_focusedIndex == index) {
        _focusedIndex = null;
      } else if (_focusedIndex != null && _focusedIndex! > index) {
        _focusedIndex = _focusedIndex! - 1;
      }
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Expanded(
          child: _blocks.isEmpty
              ? Center(
                  child: Text(l10n.emptyBlockHint,
                      style: TextStyle(
                          color: Theme.of(context).hintColor, fontSize: 15)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _blocks.length,
                  itemBuilder: (context, i) => _BlockCard(
                    key: ObjectKey(_blocks[i]),
                    block: _blocks[i],
                    focused: _focusedIndex == i,
                    canMoveUp: i > 0,
                    canMoveDown: i < _blocks.length - 1,
                    onFocus: () => setState(() => _focusedIndex = i),
                    onHtmlChanged: (html) => _updateHtml(i, html),
                    onMoveUp: () => _move(i, -1),
                    onMoveDown: () => _move(i, 1),
                    onDelete: () => _delete(i),
                    uploadMedia: widget.uploadMedia,
                  ),
                ),
        ),
        const Divider(height: 1),
        _InsertBar(onInsert: _insert, uploadMedia: widget.uploadMedia),
      ],
    );
  }
}

/// One block: rendered (WYSIWYG) when unfocused, editor card when focused,
/// with a trailing ops menu (move / delete).
class _BlockCard extends StatefulWidget {
  const _BlockCard({
    super.key,
    required this.block,
    required this.focused,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onFocus,
    required this.onHtmlChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    this.uploadMedia,
  });

  final ContentBlock block;
  final bool focused;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onFocus;
  final ValueChanged<String> onHtmlChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final MediaUploader? uploadMedia;

  @override
  State<_BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends State<_BlockCard> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.focused ? null : widget.onFocus,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.focused
                  ? scheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBody(context)),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(Icons.drag_handle,
                    size: 18,
                    color: Theme.of(context).hintColor),
                onSelected: (v) {
                  switch (v) {
                    case 'up':
                      widget.onMoveUp();
                    case 'down':
                      widget.onMoveDown();
                    case 'delete':
                      widget.onDelete();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'up',
                      enabled: widget.canMoveUp,
                      child: Text(l10n.moveUp)),
                  PopupMenuItem(
                      value: 'down',
                      enabled: widget.canMoveDown,
                      child: Text(l10n.moveDown)),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                      value: 'delete', child: Text(l10n.deleteBlock)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!widget.focused) {
      // WYSIWYG rendering of the block as it will appear on the blog.
      // Tables render natively (fwfh core draws no grid lines, and the
      // user must always see the cell structure).
      if (widget.block.type == BlockType.table) {
        return _ReadOnlyTable(widget.block.html);
      }
      return HtmlWidget(
        widget.block.serialize(),
        textStyle: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontSize: 15, height: 1.6),
        customWidgetBuilder: videoPlaceholderBuilder,
      );
    }

    return switch (widget.block.type) {
      BlockType.paragraph => _TextBlockField(
          controllerSeed: _paragraphInner(widget.block.html),
          onChanged: (inner) =>
              widget.onHtmlChanged(_wrapParagraph(inner, widget.block)),
          multiline: true,
        ),
      BlockType.heading => _HeadingField(
          block: widget.block, onChanged: widget.onHtmlChanged),
      BlockType.image => _ImageField(
          block: widget.block,
          onChanged: widget.onHtmlChanged,
          uploadMedia: widget.uploadMedia),
      BlockType.table => _TableField(
          block: widget.block, onChanged: widget.onHtmlChanged),
      BlockType.video => _VideoField(
          block: widget.block,
          onChanged: widget.onHtmlChanged,
          uploadMedia: widget.uploadMedia),
      // Lists, quotes, code and unknown markup edit their raw HTML — the
      // only lossless option — while unfocused rendering stays WYSIWYG.
      _ => _TextBlockField(
          controllerSeed: widget.block.html,
          onChanged: widget.onHtmlChanged,
          multiline: true,
          mono: true,
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Paragraph helpers: edit inner text, keep the original <p> wrapper/attrs.
// ---------------------------------------------------------------------------

String _paragraphInner(String html) {
  final m = RegExp(r'^\s*<p[^>]*>([\s\S]*)</p>\s*$', caseSensitive: false)
      .firstMatch(html);
  return m?.group(1) ?? html;
}

String _wrapParagraph(String inner, ContentBlock block) {
  final m =
      RegExp(r'^\s*(<p[^>]*>)[\s\S]*(</p>)\s*$', caseSensitive: false)
          .firstMatch(block.html);
  if (m != null) return '${m.group(1)}$inner${m.group(2)}';
  return '<p>$inner</p>';
}

// ---------------------------------------------------------------------------
// Shared text field with an inline-format mini toolbar.
// ---------------------------------------------------------------------------

class _TextBlockField extends StatefulWidget {
  const _TextBlockField({
    required this.controllerSeed,
    required this.onChanged,
    required this.multiline,
    this.mono = false,
  });

  final String controllerSeed;
  final ValueChanged<String> onChanged;
  final bool multiline;
  final bool mono;

  @override
  State<_TextBlockField> createState() => _TextBlockFieldState();
}

class _TextBlockFieldState extends State<_TextBlockField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.controllerSeed);
  }

  void _wrap(String open, String close) {
    final sel = _controller.selection;
    final text = _controller.text;
    if (!sel.isValid) return;
    final selected = sel.textInside(text);
    _controller.value = _controller.value.copyWith(
      text: text.replaceRange(sel.start, sel.end, '$open$selected$close'),
      selection:
          TextSelection.collapsed(offset: sel.start + open.length + selected.length),
    );
    widget.onChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 2,
          children: [
            _MiniTool(icon: Icons.format_bold, tooltip: l10n.bold, onTap: () => _wrap('<strong>', '</strong>')),
            _MiniTool(icon: Icons.format_italic, tooltip: l10n.italic, onTap: () => _wrap('<em>', '</em>')),
            _MiniTool(icon: Icons.format_underlined, tooltip: l10n.underline, onTap: () => _wrap('<u>', '</u>')),
            _MiniTool(icon: Icons.format_strikethrough, tooltip: l10n.strikethrough, onTap: () => _wrap('<s>', '</s>')),
            _MiniTool(icon: Icons.link, tooltip: l10n.insertLink, onTap: () => _wrap('<a href="https://">', '</a>')),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          maxLines: widget.multiline ? null : 1,
          minLines: widget.multiline ? 2 : 1,
          keyboardType: TextInputType.multiline,
          style: widget.mono
              ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
              : Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.6),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
          ),
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}

class _MiniTool extends StatelessWidget {
  const _MiniTool(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 17),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Heading: level selector + inner text.
// ---------------------------------------------------------------------------

class _HeadingField extends StatefulWidget {
  const _HeadingField({required this.block, required this.onChanged});

  final ContentBlock block;
  final ValueChanged<String> onChanged;

  @override
  State<_HeadingField> createState() => _HeadingFieldState();
}

class _HeadingFieldState extends State<_HeadingField> {
  late int _level;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _level = headingLevel(widget.block.html);
    final m = RegExp(r'^\s*<h[1-6][^>]*>([\s\S]*)</h[1-6]>\s*$',
            caseSensitive: false)
        .firstMatch(widget.block.html);
    _controller = TextEditingController(text: m?.group(1) ?? widget.block.html);
  }

  void _emit() => widget.onChanged('<h$_level>${_controller.text}</h$_level>');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<int>(
          value: _level,
          underline: const SizedBox.shrink(),
          items: [
            for (var i = 1; i <= 6; i++)
              DropdownMenuItem(value: i, child: Text('H$i')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _level = v);
            _emit();
          },
        ),
        TextField(
          controller: _controller,
          maxLines: null,
          style: Theme.of(context).textTheme.titleLarge,
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            hintText: l10n.headingBlock,
          ),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Image: preview + src / alt / caption, with device-pick upload.
// ---------------------------------------------------------------------------

class _ImageField extends StatefulWidget {
  const _ImageField({
    required this.block,
    required this.onChanged,
    this.uploadMedia,
  });

  final ContentBlock block;
  final ValueChanged<String> onChanged;
  final MediaUploader? uploadMedia;

  @override
  State<_ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends State<_ImageField> {
  late final TextEditingController _srcCtrl;
  late final TextEditingController _altCtrl;
  late final TextEditingController _captionCtrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _srcCtrl = TextEditingController(text: firstImgSrc(widget.block.html) ?? '');
    _altCtrl = TextEditingController(text: firstImgAlt(widget.block.html) ?? '');
    final cap = RegExp(r'<figcaption[^>]*>([\s\S]*?)</figcaption>',
            caseSensitive: false)
        .firstMatch(widget.block.html);
    _captionCtrl = TextEditingController(text: cap?.group(1)?.trim() ?? '');
  }

  @override
  void dispose() {
    _srcCtrl.dispose();
    _altCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final img =
        '<img src="${_srcCtrl.text.trim()}" alt="${_altCtrl.text.trim()}" />';
    widget.onChanged(_captionCtrl.text.trim().isEmpty
        ? img
        : '<figure>$img<figcaption>${_captionCtrl.text.trim()}</figcaption></figure>');
  }

  Future<void> _pickAndUpload() async {
    final l10n = AppLocalizations.of(context)!;
    final uploader = widget.uploadMedia;
    if (uploader == null) return;
    final xfile = await imgpick.ImagePicker().pickImage(
        imageQuality: 90, maxWidth: 2560, source: imgpick.ImageSource.gallery);
    if (xfile == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xfile.readAsBytes();
      final (name, mime) = normalizeImageUpload(
          xfile.name, xfile.mimeType ?? 'image/jpeg');
      final result = await uploader(name, bytes, mime);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _srcCtrl.text = result.url;
        if (_altCtrl.text.trim().isEmpty) _altCtrl.text = xfile.name;
      });
      _emit();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mediaUploadErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_srcCtrl.text.trim().isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(_srcCtrl.text.trim(),
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        const SizedBox(height: 6),
        TextField(
          controller: _srcCtrl,
          decoration: InputDecoration(
              labelText: l10n.imageUrl,
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _uploading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (widget.uploadMedia == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.photo_library),
                          tooltip: l10n.pickFromDevice,
                          onPressed: _pickAndUpload,
                        ))),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _altCtrl,
          decoration: InputDecoration(
              labelText: l10n.altText,
              isDense: true,
              border: const OutlineInputBorder()),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _captionCtrl,
          decoration: InputDecoration(
              labelText: l10n.captionLabel,
              isDense: true,
              border: const OutlineInputBorder()),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Video: URL field, embed builder.
// ---------------------------------------------------------------------------

class _VideoField extends StatefulWidget {
  const _VideoField({
    required this.block,
    required this.onChanged,
    this.uploadMedia,
  });

  final ContentBlock block;
  final ValueChanged<String> onChanged;
  final MediaUploader? uploadMedia;

  @override
  State<_VideoField> createState() => _VideoFieldState();
}

class _VideoFieldState extends State<_VideoField> {
  late final TextEditingController _url;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: firstEmbedUrl(widget.block.html) ?? '');
  }

  Future<void> _pickAndUpload() async {
    final l10n = AppLocalizations.of(context)!;
    final uploader = widget.uploadMedia;
    if (uploader == null) return;
    final xfile = await imgpick.ImagePicker()
        .pickVideo(source: imgpick.ImageSource.gallery);
    if (xfile == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xfile.readAsBytes();
      final result = await uploader(
          xfile.name, bytes, xfile.mimeType ?? 'video/mp4');
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _url.text = result.url;
      });
      // A locally uploaded file becomes a wp:video block.
      widget.block.wpOpen = '<!-- wp:video -->';
      widget.block.wpClose = '<!-- /wp:video -->';
      widget.onChanged('<video controls src="${result.url}"></video>');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mediaUploadErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.play_circle_outline, size: 34),
          title: Text(l10n.videoBlock),
          subtitle: Text(_url.text,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        TextField(
          controller: _url,
          decoration: InputDecoration(
              labelText: l10n.videoUrl,
              hintText: l10n.videoUrlHint,
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _uploading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (widget.uploadMedia == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.video_library),
                          tooltip: l10n.pickVideoFromDevice,
                          onPressed: _pickAndUpload,
                        ))),
          onChanged: (v) {
            if (v.trim().isEmpty) return;
            widget.onChanged(buildVideoEmbed(v.trim()));
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Table: editable cell grid with row/column controls.
// ---------------------------------------------------------------------------

/// Read-only bordered table used for the unfocused (WYSIWYG) rendering —
/// the HTML renderer draws no grid lines and the cell structure must be
/// visible at all times.
class _ReadOnlyTable extends StatelessWidget {
  const _ReadOnlyTable(this.html);

  final String html;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final table = parseTable(html);
    if (table.rows.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: scheme.outlineVariant),
        children: [
          for (var r = 0; r < table.rows.length; r++)
            TableRow(
              decoration: r == 0 && table.hasHeader
                  ? BoxDecoration(
                      color: scheme.secondaryContainer.withValues(alpha: 0.4))
                  : null,
              children: [
                for (var c = 0; c < table.rows[r].length; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: Text(
                      table.rows[r][c],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: r == 0 && table.hasHeader
                            ? FontWeight.w700
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TableField extends StatefulWidget {
  const _TableField({required this.block, required this.onChanged});

  final ContentBlock block;
  final ValueChanged<String> onChanged;

  @override
  State<_TableField> createState() => _TableFieldState();
}

class _TableFieldState extends State<_TableField> {
  late TableData _table;

  /// One cached controller per cell so rebuilds (which happen on every
  /// keystroke via the emit chain) never reset the caret.
  final List<List<TextEditingController>> _cellCtrls = [];

  @override
  void initState() {
    super.initState();
    _table = parseTable(widget.block.html);
    if (_table.rows.isEmpty) {
      _table = TableData(rows: [
        ['', ''],
        ['', ''],
      ], hasHeader: true, hasBorder: true);
    }
    _syncControllers();
  }

  @override
  void dispose() {
    for (final row in _cellCtrls) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _syncControllers() {
    while (_cellCtrls.length < _table.rows.length) {
      _cellCtrls.add(<TextEditingController>[]);
    }
    while (_cellCtrls.length > _table.rows.length) {
      for (final c in _cellCtrls.removeLast()) {
        c.dispose();
      }
    }
    for (var r = 0; r < _table.rows.length; r++) {
      final rowCtrls = _cellCtrls[r];
      while (rowCtrls.length < _table.rows[r].length) {
        rowCtrls.add(TextEditingController(
            text: _table.rows[r][rowCtrls.length]));
      }
      while (rowCtrls.length > _table.rows[r].length) {
        rowCtrls.removeLast().dispose();
      }
    }
  }

  void _emit() => widget.onChanged(serializeTable(_table, wrapFigure: false));

  void _addRow() {
    setState(() {
      _table.rows.add(List.filled(_table.columnCount, ''));
      _syncControllers();
    });
    _emit();
  }

  void _addColumn() {
    setState(() {
      for (final row in _table.rows) {
        row.add('');
      }
      _syncControllers();
    });
    _emit();
  }

  void _removeRow() {
    if (_table.rows.isEmpty) return;
    setState(() {
      _table.rows.removeLast();
      _syncControllers();
    });
    _emit();
  }

  void _removeColumn() {
    if (_table.columnCount <= 1) return;
    setState(() {
      for (final row in _table.rows) {
        if (row.isNotEmpty) row.removeLast();
      }
      _syncControllers();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: scheme.outlineVariant, width: 0.5),
            children: [
              for (var r = 0; r < _table.rows.length; r++)
                TableRow(
                  decoration: r == 0 && _table.hasHeader
                      ? BoxDecoration(
                          color: scheme.secondaryContainer
                              .withValues(alpha: 0.4))
                      : null,
                  children: [
                    for (var c = 0; c < _table.rows[r].length; c++)
                      TableCell(
                        child: TextField(
                          controller: _cellCtrls[r][c],
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: r == 0 && _table.hasHeader
                                ? FontWeight.w700
                                : null,
                          ),
                          onChanged: (v) {
                            _table.rows[r][c] = v;
                            _emit();
                          },
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          children: [
            ActionChip(label: Text(l10n.addRow), onPressed: _addRow),
            ActionChip(label: Text(l10n.removeRow), onPressed: _removeRow),
            ActionChip(label: Text(l10n.addColumn), onPressed: _addColumn),
            ActionChip(
                label: Text(l10n.removeColumn), onPressed: _removeColumn),
            FilterChip(
              label: Text(l10n.tableHeaderRow),
              selected: _table.hasHeader,
              onSelected: (v) {
                setState(() => _table.hasHeader = v);
                _emit();
              },
            ),
            FilterChip(
              label: Text(l10n.tableBorder),
              selected: _table.hasBorder,
              onSelected: (v) {
                setState(() => _table.hasBorder = v);
                _emit();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Insert bar at the bottom of the visual editor.
// ---------------------------------------------------------------------------

class _InsertBar extends StatelessWidget {
  const _InsertBar({required this.onInsert, this.uploadMedia});

  final ValueChanged<ContentBlock> onInsert;
  final MediaUploader? uploadMedia;

  Future<void> _insertImage(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final fromDevice = uploadMedia == null
        ? false
        : await showModalBottomSheet<bool>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: Text(l10n.pickFromDevice),
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(l10n.enterImageUrl),
                    onTap: () => Navigator.of(sheetContext).pop(false),
                  ),
                ],
              ),
            ),
          );
    if (fromDevice == null || !context.mounted) return;

    if (fromDevice) {
      // Pick, upload, then insert an image block with the result URL.
      final xfile = await imgpick.ImagePicker().pickImage(
          imageQuality: 90, maxWidth: 2560, source: imgpick.ImageSource.gallery);
      if (xfile == null || !context.mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(l10n.uploadingImage),
          ]),
        ),
      );
      try {
        final bytes = await xfile.readAsBytes();
        final (name, mime) = normalizeImageUpload(
            xfile.name, xfile.mimeType ?? 'image/jpeg');
        final result = await uploadMedia!(name, bytes, mime);
        if (context.mounted) Navigator.of(context).pop();
        onInsert(ContentBlock(
          type: BlockType.image,
          html: '<figure><img src="${result.url}" alt="${xfile.name}" /></figure>',
          wpOpen: '<!-- wp:image -->',
          wpClose: '<!-- /wp:image -->',
        ));
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(mediaUploadErrorText(l10n, e))));
        }
      }
      return;
    }

    final url = await _prompt(context, l10n.imageUrl, 'https://');
    if (url == null || url.isEmpty || !context.mounted) return;
    final alt = await _prompt(context, l10n.altText, '');
    onInsert(ContentBlock(
      type: BlockType.image,
      html: '<img src="$url" alt="${alt ?? ''}" />',
      wpOpen: '<!-- wp:image -->',
      wpClose: '<!-- /wp:image -->',
    ));
  }

  /// Video insert: device pick & upload (wp:video block) or URL embed.
  Future<void> _insertVideo(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final fromDevice = uploadMedia == null
        ? false
        : await showModalBottomSheet<bool>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.video_library),
                    title: Text(l10n.pickVideoFromDevice),
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(l10n.enterVideoUrl),
                    onTap: () => Navigator.of(sheetContext).pop(false),
                  ),
                ],
              ),
            ),
          );
    if (fromDevice == null || !context.mounted) return;

    if (fromDevice) {
      final xfile = await imgpick.ImagePicker()
          .pickVideo(source: imgpick.ImageSource.gallery);
      if (xfile == null || !context.mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(l10n.uploadingVideo)),
          ]),
        ),
      );
      try {
        final bytes = await xfile.readAsBytes();
        final result = await uploadMedia!(
            xfile.name, bytes, xfile.mimeType ?? 'video/mp4');
        if (context.mounted) Navigator.of(context).pop();
        onInsert(ContentBlock(
          type: BlockType.video,
          html: '<video controls src="${result.url}"></video>',
          wpOpen: '<!-- wp:video -->',
          wpClose: '<!-- /wp:video -->',
        ));
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(mediaUploadErrorText(l10n, e))));
        }
      }
      return;
    }

    final url = await _prompt(context, l10n.videoUrl, 'https://');
    if (url == null || url.trim().isEmpty || !context.mounted) return;
    onInsert(ContentBlock(
      type: BlockType.video,
      html: buildVideoEmbed(url.trim()),
      wpOpen: '<!-- wp:embed -->',
      wpClose: '<!-- /wp:embed -->',
    ));
  }

  Future<String?> _prompt(BuildContext context, String title, String hint) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: hint);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(l10n.ok)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.text_fields, size: 18),
            label: Text(l10n.paragraphBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.paragraph,
              html: '<p></p>',
              wpOpen: '<!-- wp:paragraph -->',
              wpClose: '<!-- /wp:paragraph -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.title, size: 18),
            label: Text(l10n.headingBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.heading,
              html: '<h2></h2>',
              wpOpen: '<!-- wp:heading -->',
              wpClose: '<!-- /wp:heading -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.image, size: 18),
            label: Text(l10n.imageBlock),
            onPressed: () => _insertImage(context),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.table_chart, size: 18),
            label: Text(l10n.tableBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.table,
              html: buildTable(),
              wpOpen: '<!-- wp:table -->',
              wpClose: '<!-- /wp:table -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.play_circle_outline, size: 18),
            label: Text(l10n.videoBlock),
            onPressed: () => _insertVideo(context),
          ),
        ],
      ),
    );
  }
}
