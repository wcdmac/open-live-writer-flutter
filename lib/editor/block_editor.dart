import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:image_picker/image_picker.dart' as imgpick;

import '../l10n/app_localizations.dart';
import '../services/media_cache.dart';
import '../views/editor/editor_toolbar.dart'
    show MediaUploader, mediaUploadErrorText;
import 'block_document.dart';
import 'editor_controller.dart';
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
part 'blocks/cover_image_field.dart';
part 'blocks/gallery_field.dart';
part 'blocks/button_field.dart';
part 'blocks/columns_field.dart';
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
  late final EditorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = EditorController(
      initialContent: widget.content,
      onChanged: widget.onContentChanged,
    );
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() => setState(() {});

  @override
  void didUpdateWidget(BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The controller skips an echo of its own output, so a background-loaded
    // post that equals what we last emitted won't reset caret/focus.
    _controller.updateFromExternal(widget.content);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final blocks = _controller.blocks;
    final focusedIndex = _controller.focusedIndex;
    return Column(
      children: [
        Expanded(
          child: blocks.isEmpty
              ? Center(
                  child: Text(l10n.emptyBlockHint,
                      style: TextStyle(
                          color: Theme.of(context).hintColor, fontSize: 15)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: blocks.length,
                  itemBuilder: (context, i) => _BlockCard(
                    key: ObjectKey(blocks[i]),
                    block: blocks[i],
                    focused: focusedIndex == i,
                    canMoveUp: i > 0,
                    canMoveDown: i < blocks.length - 1,
                    onFocus: () => _controller.focus(i),
                    onHtmlChanged: (html) => _controller.updateHtml(i, html),
                    onMoveUp: () => _controller.move(i, -1),
                    onMoveDown: () => _controller.move(i, 1),
                    onDelete: () => _controller.delete(i),
                    uploadMedia: widget.uploadMedia,
                  ),
                ),
        ),
        const Divider(height: 1),
        _InsertBar(onInsert: _controller.insert, uploadMedia: widget.uploadMedia),
      ],
    );
  }
}
