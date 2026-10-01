part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// List block: per-item fields with a shared inline-format toolbar that
// targets the focused item.
// ---------------------------------------------------------------------------

class _ListField extends StatefulWidget {
  const _ListField({required this.block, required this.onChanged});

  final ContentBlock block;
  final ValueChanged<String> onChanged;

  @override
  State<_ListField> createState() => _ListFieldState();
}

class _ListFieldState extends State<_ListField> {
  late final ListData _list;
  final List<TextEditingController> _ctrls = [];
  int? _focusedIdx;

  @override
  void initState() {
    super.initState();
    _list = parseList(widget.block.html);
    _syncCtrls();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncCtrls() {
    while (_ctrls.length < _list.items.length) {
      _ctrls.add(TextEditingController(
          text: _ctrls.length < _list.items.length
              ? _list.items[_ctrls.length]
              : ''));
    }
    while (_ctrls.length > _list.items.length) {
      _ctrls.removeLast().dispose();
    }
    // Keep controller texts in sync after add/remove reorders indices.
    for (var i = 0; i < _ctrls.length; i++) {
      if (_ctrls[i].text != _list.items[i]) {
        _ctrls[i].text = _list.items[i];
      }
    }
  }

  void _emit() => widget.onChanged(buildListHtml(_list));

  void _wrapFocused(String open, String close) {
    final idx = _focusedIdx;
    if (idx == null || idx >= _ctrls.length) return;
    final c = _ctrls[idx];
    final sel = c.selection;
    if (!sel.isValid) return;
    final selected = sel.textInside(c.text);
    c.value = c.value.copyWith(
      text: c.text.replaceRange(sel.start, sel.end, '$open$selected$close'),
      selection: TextSelection.collapsed(
          offset: sel.start + open.length + selected.length),
    );
    _list.items[idx] = c.text;
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 2,
          children: [
            _MiniTool(icon: Icons.format_bold, tooltip: l10n.bold, onTap: () => _wrapFocused('<strong>', '</strong>')),
            _MiniTool(icon: Icons.format_italic, tooltip: l10n.italic, onTap: () => _wrapFocused('<em>', '</em>')),
            _MiniTool(icon: Icons.link, tooltip: l10n.insertLink, onTap: () => _wrapFocused('<a href="https://">', '</a>')),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.format_list_bulleted, size: 18)),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.format_list_numbered, size: 18)),
              ],
              selected: {_list.ordered},
              onSelectionChanged: (s) {
                setState(() => _list.ordered = s.first);
                _emit();
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _list.items.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _list.ordered
                    ? Text('${i + 1}.',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 14))
                    : Icon(Icons.circle,
                        size: 6, color: scheme.onSurfaceVariant),
              ),
              Expanded(
                child: TextField(
                  controller: _ctrls[i],
                  onTap: () => _focusedIdx = i,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontSize: 15, height: 1.6),
                  onChanged: (v) {
                    _list.items[i] = v;
                    _emit();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: l10n.removeItem,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _list.items.removeAt(i);
                    _syncCtrls();
                  });
                  _emit();
                },
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.addItem),
            onPressed: () {
              setState(() {
                _list.items.add('');
                _syncCtrls();
                _focusedIdx = _list.items.length - 1;
              });
              _emit();
            },
          ),
        ),
      ],
    );
  }
}
