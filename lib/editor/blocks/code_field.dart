part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Code block: edit the plain-text payload, serialize as core/code.
// ---------------------------------------------------------------------------

/// Focused code editor: multi-line mono field; re-serializes to Gutenberg
/// core/code markup on every change.
class _CodeField extends StatefulWidget {
  const _CodeField({required this.block, required this.onChanged});

  final ContentBlock block;
  final ValueChanged<String> onChanged;

  @override
  State<_CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<_CodeField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: parseCodeBlock(widget.block.html));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      maxLines: null,
      minLines: 3,
      keyboardType: TextInputType.multiline,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        color: scheme.onSurface,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.all(12),
      ),
      onChanged: (text) => widget.onChanged(buildCodeHtml(text)),
    );
  }
}
