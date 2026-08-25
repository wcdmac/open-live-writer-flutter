import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// Formatting toolbar that wraps the selection in HTML tags — the same
/// content model as the original OLW editor (posts are HTML).
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.controller,
    required this.onContentChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onContentChanged;

  void _wrapSelection(String open, String close) {
    final selection = controller.selection;
    final text = controller.text;
    if (!selection.isValid) return;

    final selected = selection.textInside(text);
    final start = selection.start;
    final end = selection.end;
    final replacement = '$open$selected$close';

    controller.value = controller.value.copyWith(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + open.length + selected.length),
    );
    onContentChanged(controller.text);
  }

  void _insertAtCursor(String snippet) {
    final selection = controller.selection;
    final text = controller.text;
    final offset = selection.isValid ? selection.baseOffset : text.length;

    controller.value = controller.value.copyWith(
      text: text.replaceRange(offset, offset, snippet),
      selection: TextSelection.collapsed(offset: offset + snippet.length),
    );
    onContentChanged(controller.text);
  }

  Future<void> _insertLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final url = await _prompt(context, l10n.linkUrl, 'https://');
    if (url == null || url.isEmpty) return;
    final sel = controller.selection.textInside(controller.text);
    _wrapSelection('<a href="$url">', '</a>');
    if (sel.isEmpty) {
      // Put a friendly placeholder between the tags.
      final text = controller.text;
      final pos = controller.selection.baseOffset;
      controller.value = controller.value.copyWith(
        text: text.replaceRange(pos - 4, pos - 4, 'link text'),
      );
      onContentChanged(controller.text);
    }
  }

  Future<void> _insertImage(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final url = await _prompt(context, l10n.imageUrl, 'https://');
    if (url == null || url.isEmpty || !context.mounted) return;
    final alt = await _prompt(context, l10n.altText, '');
    _insertAtCursor('<img src="$url" alt="${alt ?? ''}" />');
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
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        _ToolButton(
          icon: Icons.format_bold,
          tooltip: l10n.bold,
          onTap: () => _wrapSelection('<strong>', '</strong>'),
        ),
        _ToolButton(
          icon: Icons.format_italic,
          tooltip: l10n.italic,
          onTap: () => _wrapSelection('<em>', '</em>'),
        ),
        _ToolButton(
          icon: Icons.format_underlined,
          tooltip: l10n.underline,
          onTap: () => _wrapSelection('<u>', '</u>'),
        ),
        _ToolButton(
          icon: Icons.format_strikethrough,
          tooltip: l10n.strikethrough,
          onTap: () => _wrapSelection('<s>', '</s>'),
        ),
        const _Divider(),
        _ToolButton(
          label: 'H2',
          tooltip: l10n.h2,
          onTap: () => _wrapSelection('<h2>', '</h2>'),
        ),
        _ToolButton(
          label: 'H3',
          tooltip: l10n.h3,
          onTap: () => _wrapSelection('<h3>', '</h3>'),
        ),
        _ToolButton(
          icon: Icons.format_quote,
          tooltip: l10n.blockquote,
          onTap: () => _wrapSelection('<blockquote>', '</blockquote>'),
        ),
        const _Divider(),
        _ToolButton(
          icon: Icons.format_list_bulleted,
          tooltip: l10n.bulletList,
          onTap: () => _insertAtCursor('<ul>\n  <li>Item</li>\n</ul>\n'),
        ),
        _ToolButton(
          icon: Icons.format_list_numbered,
          tooltip: l10n.numberedList,
          onTap: () => _insertAtCursor('<ol>\n  <li>Item</li>\n</ol>\n'),
        ),
        const _Divider(),
        _ToolButton(
          icon: Icons.link,
          tooltip: l10n.insertLink,
          onTap: () => _insertLink(context),
        ),
        _ToolButton(
          icon: Icons.image,
          tooltip: l10n.insertImage,
          onTap: () => _insertImage(context),
        ),
        _ToolButton(
          icon: Icons.code,
          tooltip: l10n.codeBlock,
          onTap: () => _wrapSelection('<pre><code>', '</code></pre>'),
        ),
        _ToolButton(
          icon: Icons.more_horiz,
          tooltip: l10n.moreTag,
          onTap: () => _insertAtCursor('<!--more-->'),
        ),
        const _Divider(),
        _ToolButton(
          icon: Icons.content_copy,
          tooltip: l10n.copyHtml,
          onTap: () => Clipboard.setData(
              ClipboardData(text: controller.text)),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData? icon;
  final String? label;
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
          padding: const EdgeInsets.all(6),
          child: icon != null
              ? Icon(icon, size: 18)
              : Text(
                  label!,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 1, indent: 4, endIndent: 4);
}

/// SnackBar helper shared by editor actions.
void showEditorSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
