part of '../block_editor.dart';

/// Read-only bordered table used for the unfocused (WYSIWYG) rendering —
/// the HTML renderer draws no grid lines and the cell structure must be
/// visible at all times.
class _ReadOnlyTable extends StatefulWidget {
  const _ReadOnlyTable(this.html);

  final String html;

  @override
  State<_ReadOnlyTable> createState() => _ReadOnlyTableState();
}

class _ReadOnlyTableState extends State<_ReadOnlyTable> {
  TableData? _table;
  String? _parsedFrom;

  /// Parses once per distinct html. `parseTable` compiles several RegExps,
  /// so running it inside build re-paid that cost on every card rebuild.
  void _parse() {
    if (_parsedFrom == widget.html) return;
    _parsedFrom = widget.html;
    _table = parseTable(widget.html);
  }

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(_ReadOnlyTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _parse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final table = _table;
    if (table == null || table.rows.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        // Always bordered in-app: the HTML source has no inline borders
        // (they break Gutenberg validation) so cell structure must stay
        // visible here.
        border: TableBorder.all(color: scheme.outlineVariant),
        children: [
          for (var r = 0; r < table.rows.length; r++)
            TableRow(
              decoration: r == 0 && table.hasHeader
                  ? BoxDecoration(
                      color: scheme.secondaryContainer.withValues(alpha: 0.4))
                  : null,
              children: [
                for (var c = 0; c < table.rows[r].length; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: Text(
                      table.rows[r][c],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: r == 0 && table.hasHeader
                            ? FontWeight.w700
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Read-only code rendering for the unfocused (WYSIWYG) view. Rendered
/// natively so the HTML renderer never interprets the source inside.
class _ReadOnlyCode extends StatefulWidget {
  const _ReadOnlyCode(this.html);

  final String html;

  @override
  State<_ReadOnlyCode> createState() => _ReadOnlyCodeState();
}

class _ReadOnlyCodeState extends State<_ReadOnlyCode> {
  String? _code;
  String? _parsedFrom;

  /// Parses once per distinct html (see [_ReadOnlyTableState._parse]).
  void _parse() {
    if (_parsedFrom == widget.html) return;
    _parsedFrom = widget.html;
    _code = parseCodeBlock(widget.html) ?? widget.html;
  }

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(_ReadOnlyCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    _parse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = _code ?? widget.html;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
