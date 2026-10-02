part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Button: visible label + link target.
// ---------------------------------------------------------------------------

class _ButtonField extends StatefulWidget {
  const _ButtonField({required this.block, required this.onChanged});

  final ContentBlock block;
  final ValueChanged<String> onChanged;

  @override
  State<_ButtonField> createState() => _ButtonFieldState();
}

class _ButtonFieldState extends State<_ButtonField> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    final data = parseButton(widget.block.html) ?? ButtonData(label: '');
    _labelCtrl = TextEditingController(text: data.label);
    _urlCtrl = TextEditingController(text: data.url);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(buildButtonHtml(ButtonData(
        label: _labelCtrl.text,
        url: _urlCtrl.text.trim(),
      )));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _labelCtrl,
          decoration: InputDecoration(
            labelText: l10n.buttonLabel,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _urlCtrl,
          decoration: InputDecoration(
            labelText: l10n.linkUrl,
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: 'https://',
          ),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }
}
