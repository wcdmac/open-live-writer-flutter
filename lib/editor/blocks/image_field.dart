part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Image: preview + src / alt / caption, with device-pick upload.
// ---------------------------------------------------------------------------

class _ImageField extends StatefulWidget {
  const _ImageField({
    required this.block,
    required this.onChanged,
    this.uploadMedia,
  });

  final ContentBlock block;
  final ValueChanged<String> onChanged;
  final MediaUploader? uploadMedia;

  @override
  State<_ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends State<_ImageField> {
  late final TextEditingController _srcCtrl;
  late final TextEditingController _altCtrl;
  late final TextEditingController _captionCtrl;
  bool _uploading = false;

  /// Original figure class (is-resized, alignwide…) and img attributes
  /// (width/height/id/class) — preserved on emit so editing alt text or
  /// caption doesn't reset the image's layout settings.
  String? _figureClass;
  String? _imgAttrs;

  @override
  void initState() {
    super.initState();
    _srcCtrl = TextEditingController(text: firstImgSrc(widget.block.html) ?? '');
    _altCtrl = TextEditingController(text: firstImgAlt(widget.block.html) ?? '');
    final cap = RegExp(r'<figcaption[^>]*>([\s\S]*?)</figcaption>',
            caseSensitive: false)
        .firstMatch(widget.block.html);
    _captionCtrl = TextEditingController(text: cap?.group(1)?.trim() ?? '');

    final figureClass = RegExp(r'<figure[^>]*\bclass="([^"]*)"',
            caseSensitive: false)
        .firstMatch(widget.block.html);
    _figureClass = figureClass?.group(1)?.trim();

    // Keep every img attribute except src/alt for round-trip.
    final img = RegExp(r'<img([^>]*?)/?>', caseSensitive: false)
        .firstMatch(widget.block.html);
    if (img != null) {
      final kept = <String>[];
      for (final attr in RegExp(r'([\w-]+)\s*=\s*"([^"]*)"')
          .allMatches(img.group(1) ?? '')) {
        final name = attr.group(1)!.toLowerCase();
        if (name == 'src' || name == 'alt') continue;
        kept.add('${attr.group(1)}="${attr.group(2)}"');
      }
      if (kept.isNotEmpty) _imgAttrs = kept.join(' ');
    }
  }

  @override
  void dispose() {
    _srcCtrl.dispose();
    _altCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(buildImageHtml(_srcCtrl.text.trim(),
        _altCtrl.text.trim(),
        caption: _captionCtrl.text,
        figureClass: _figureClass,
        imgAttrs: _imgAttrs));
  }

  Future<void> _pickAndUpload() async {
    final l10n = AppLocalizations.of(context)!;
    final uploader = widget.uploadMedia;
    if (uploader == null) return;
    final xfile = await imgpick.ImagePicker().pickImage(
        imageQuality: kImageUploadQuality,
        maxWidth: kImageMaxWidth,
        source: imgpick.ImageSource.gallery);
    // Picking opens an external activity: the user can back out and pop this
    // route while it is open, so the State may already be disposed here.
    if (xfile == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xfile.readAsBytes();
      final (name, mime) = normalizeImageUpload(
          xfile.name, xfile.mimeType ?? 'image/jpeg');
      final result = await uploader(name, bytes, mime);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _srcCtrl.text = result.url;
        if (_altCtrl.text.trim().isEmpty) _altCtrl.text = xfile.name;
      });
      _emit();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mediaUploadErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_srcCtrl.text.trim().isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            // CachedImage: consistent with the preview/editor offline
            // strategy — a previously downloaded copy renders even when
            // the network is down.
            child: CachedImage(
                url: _srcCtrl.text.trim(),
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_) => const SizedBox.shrink()),
          ),
        const SizedBox(height: 6),
        TextField(
          controller: _srcCtrl,
          decoration: InputDecoration(
              labelText: l10n.imageUrl,
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _uploading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (widget.uploadMedia == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.photo_library),
                          tooltip: l10n.pickFromDevice,
                          onPressed: _pickAndUpload,
                        ))),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _altCtrl,
          decoration: InputDecoration(
              labelText: l10n.altText,
              isDense: true,
              border: const OutlineInputBorder()),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _captionCtrl,
          decoration: InputDecoration(
              labelText: l10n.captionLabel,
              isDense: true,
              border: const OutlineInputBorder()),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }
}
