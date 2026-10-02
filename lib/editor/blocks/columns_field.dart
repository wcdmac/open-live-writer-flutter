part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Columns: a row of independently-editable text columns. Each column is edited
// as plain text and rebuilt to a single paragraph (the common case); the
// column count is adjustable between 2 and 6.
// ---------------------------------------------------------------------------

class _ColumnsField extends StatefulWidget {
  const _ColumnsField({required this.block, required this.onChanged});

  final ContentBlock block;
  final ValueChanged<String> onChanged;

  @override
  State<_ColumnsField> createState() => _ColumnsFieldState();
}

class _ColumnsFieldState extends State<_ColumnsField> {
  late ColumnsData _data;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _data =
        parseColumns(widget.block.html) ?? ColumnsData(columns: ['', '']);
    _controllers = [
      for (final inner in _data.columns)
        TextEditingController(text: columnInnerText(inner))
    ];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    // Sync the controllers back into column inner HTML, then serialize.
    for (var i = 0; i < _controllers.length; i++) {
      _data.columns[i] = wrapColumnInner(_controllers[i].text);
    }
    widget.onChanged(buildColumnsHtml(_data));
  }

  void _addColumn() {
    if (_data.count >= 6) return;
    setState(() {
      _data.columns.add('');
      _controllers.add(TextEditingController(text: ''));
    });
    _emit();
  }

  void _removeColumn() {
    if (_data.count <= 2) return;
    setState(() {
      _data.columns.removeLast();
      _controllers.removeLast().dispose();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l10n.columnsCount,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: _data.count > 2 ? _removeColumn : null,
            ),
            Text('${_data.count}'),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: _data.count < 6 ? _addColumn : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TextField(
              controller: _controllers[i],
              decoration: InputDecoration(
                labelText: '${l10n.columns} ${i + 1}',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _emit(),
            ),
          ),
      ],
    );
  }
}
