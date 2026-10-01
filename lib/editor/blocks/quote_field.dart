part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Quote block: per-paragraph fields with the same shared toolbar pattern.
// ---------------------------------------------------------------------------

class _QuoteField extends StatefulWidget {
  const _QuoteField({required this.block, required this.onChanged});

  final ContentBlock block;
  final ValueChanged<String> onChanged;

  @override
  State<_QuoteField> createState() => _QuoteFieldState();
}

class _QuoteFieldState extends State<_QuoteField> {
  late final QuoteData _quote;
  final List<TextEditingController> _ctrls = [];
  int? _focusedIdx;

  @override
  void initState() {
    super.initState();
    _quote = parseQuote(widget.block.html) ?? QuoteData(paragraphs: []);
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
    while (_ctrls.length < _quote.paragraphs.length) {
      _ctrls.add(TextEditingController(
          text: _ctrls.length < _quote.paragraphs.length
              ? _quote.paragraphs[_ctrls.length]
              : ''));
    }
    while (_ctrls.length > _quote.paragraphs.length) {
      _ctrls.removeLast().dispose();
    }
    for (var i = 0; i < _ctrls.length; i++) {
      if (_ctrls[i].text != _quote.paragraphs[i]) {
        _ctrls[i].text = _quote.paragraphs[i];
      }
    }
  }

  void _emit() => widget.onChanged(buildQuoteHtml(_quote));

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
    _quote.paragraphs[idx] = c.text;
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(width: 3, color: scheme.primary.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 2,
            children: [
              _MiniTool(icon: Icons.format_bold, tooltip: l10n.bold, onTap: () => _wrapFocused('<strong>', '</strong>')),
              _MiniTool(icon: Icons.format_italic, tooltip: l10n.italic, onTap: () => _wrapFocused('<em>', '</em>')),
              _MiniTool(icon: Icons.link, tooltip: l10n.insertLink, onTap: () => _wrapFocused('<a href="https://">', '</a>')),
            ],
          ),
          for (var i = 0; i < _quote.paragraphs.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrls[i],
                    onTap: () => _focusedIdx = i,
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(
                            fontSize: 15,
                            height: 1.6,
                            fontStyle: FontStyle.italic),
                    onChanged: (v) {
                      _quote.paragraphs[i] = v;
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
                      _quote.paragraphs.removeAt(i);
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
              label: Text(l10n.addParagraph),
              onPressed: () {
                setState(() {
                  _quote.paragraphs.add('');
                  _syncCtrls();
                  _focusedIdx = _quote.paragraphs.length - 1;
                });
                _emit();
              },
            ),
          ),
        ],
      ),
    );
  }
}
