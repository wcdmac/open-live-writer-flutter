part of '../block_editor.dart';

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
      // Code blocks render natively: mono font, tinted background, no
      // HTML interpretation of the source inside.
      if (widget.block.type == BlockType.code) {
        return _ReadOnlyCode(widget.block.html);
      }
      return HtmlWidget(
        widget.block.serialize(),
        textStyle: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(fontSize: 15, height: 1.6),
        customWidgetBuilder: mediaPlaceholderBuilder,
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
      BlockType.code => _CodeField(
          block: widget.block, onChanged: widget.onHtmlChanged),
      BlockType.list => _ListField(
          block: widget.block, onChanged: widget.onHtmlChanged),
      BlockType.quote => _QuoteField(
          block: widget.block, onChanged: widget.onHtmlChanged),
      // Lists, quotes and unknown markup edit their raw HTML — the
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

// Hoisted: both run on every keystroke and [_paragraphInner] is also called
// from build, so compiling them per call was measurable on long documents.
final RegExp _paragraphInnerRe =
    RegExp(r'^\s*<p[^>]*>([\s\S]*)</p>\s*$', caseSensitive: false);
final RegExp _wrapParagraphRe =
    RegExp(r'^\s*(<p[^>]*>)[\s\S]*(</p>)\s*$', caseSensitive: false);

String _paragraphInner(String html) {
  final m = _paragraphInnerRe.firstMatch(html);
  return m?.group(1) ?? html;
}

String _wrapParagraph(String inner, ContentBlock block) {
  final m = _wrapParagraphRe.firstMatch(block.html);
  if (m != null) return '${m.group(1)}$inner${m.group(2)}';
  return '<p>$inner</p>';
}
