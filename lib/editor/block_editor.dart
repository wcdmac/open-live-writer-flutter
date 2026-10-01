import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:image_picker/image_picker.dart' as imgpick;

import '../l10n/app_localizations.dart';
import '../services/media_cache.dart';
import '../views/editor/editor_toolbar.dart'
    show MediaUploader, mediaUploadErrorText;
import 'block_document.dart';
import 'video_placeholder.dart';
import '../utils/constants.dart';

// Internal block widgets live in `blocks/*` so this file stays focused on the
// editor shell (state, parse/reparse, emit) while each block type is
// maintained in its own file. All share this library's imports via `part of`.
part 'blocks/block_card.dart';
part 'blocks/read_only_views.dart';
part 'blocks/text_field.dart';
part 'blocks/image_field.dart';
part 'blocks/video_field.dart';
part 'blocks/table_field.dart';
part 'blocks/code_field.dart';
part 'blocks/list_field.dart';
part 'blocks/quote_field.dart';
part 'blocks/insert_bar.dart';

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
    // Compare the raw strings first: trimming before the comparison meant an
    // external update that differed only in leading/trailing whitespace was
    // ignored, leaving the card showing stale content.
    if (widget.content != _lastEmitted &&
        widget.content.trim() != _lastEmitted.trim()) {
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
