part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Table: editable cell grid with row/column controls.
// ---------------------------------------------------------------------------

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

  // wrapFigure: wp:table blocks must contain <figure class="wp-block-table">
  // or Gutenberg flags the block as invalid content.
  void _emit() => widget.onChanged(serializeTable(_table, wrapFigure: true));

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
                          textAlign: switch (_table.align) {
                            TableCellAlign.left => TextAlign.left,
                            TableCellAlign.center => TextAlign.center,
                            TableCellAlign.right => TextAlign.right,
                          },
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
            // No border toggle: inline border styles break Gutenberg block
            // validation; frontend borders come from WordPress core styles.
            SegmentedButton<TableCellAlign>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                ButtonSegment(
                  value: TableCellAlign.left,
                  icon: const Icon(Icons.format_align_left),
                  tooltip: l10n.alignLeft,
                ),
                ButtonSegment(
                  value: TableCellAlign.center,
                  icon: const Icon(Icons.format_align_center),
                  tooltip: l10n.alignCenter,
                ),
                ButtonSegment(
                  value: TableCellAlign.right,
                  icon: const Icon(Icons.format_align_right),
                  tooltip: l10n.alignRight,
                ),
              ],
              selected: {_table.align},
              onSelectionChanged: (s) {
                setState(() => _table.align = s.first);
                _emit();
              },
            ),
          ],
        ),
      ],
    );
  }
}
