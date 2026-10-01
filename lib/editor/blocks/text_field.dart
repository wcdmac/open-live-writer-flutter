part of '../block_editor.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  /// Original `<hN ...>` attributes (class/id) — preserved on emit so
  /// editing text doesn't strip them.
  String _attrs = '';

  @override
  void initState() {
    super.initState();
    _level = headingLevel(widget.block.html);
    final m = RegExp(r'^\s*<h[1-6]([^>]*)>([\s\S]*)</h[1-6]>\s*$',
            caseSensitive: false)
        .firstMatch(widget.block.html);
    _attrs = m?.group(1)?.trim() ?? '';
    _controller = TextEditingController(text: m?.group(2) ?? widget.block.html);
  }

  void _emit() => widget.onChanged(
      '<h$_level${_attrs.isEmpty ? '' : ' $_attrs'}>'
      '${_controller.text}</h$_level>');

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
