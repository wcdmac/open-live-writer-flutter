part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Cover image: background URL + optional overlay text, with device-pick upload.
// ---------------------------------------------------------------------------

class _CoverImageField extends StatefulWidget {
  const _CoverImageField({
    required this.block,
    required this.onChanged,
    this.uploadMedia,
  });

  final ContentBlock block;
  final ValueChanged<String> onChanged;
  final MediaUploader? uploadMedia;

  @override
  State<_CoverImageField> createState() => _CoverImageFieldState();
}

class _CoverImageFieldState extends State<_CoverImageField> {
  late final TextEditingController _srcCtrl;
  late final TextEditingController _overlayCtrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final data = parseCover(widget.block.html) ?? CoverData(url: '');
    _srcCtrl = TextEditingController(text: data.url);
    _overlayCtrl = TextEditingController(text: data.overlay);
  }

  @override
  void dispose() {
    _srcCtrl.dispose();
    _overlayCtrl.dispose();
    super.dispose();
  }

  void _emit() =>
      widget.onChanged(buildCoverHtml(CoverData(
        url: _srcCtrl.text.trim(),
        overlay: _overlayCtrl.text,
      )));

  Future<void> _pickAndUpload() async {
    final l10n = AppLocalizations.of(context)!;
    final uploader = widget.uploadMedia;
    if (uploader == null) return;
    final xfile = await imgpick.ImagePicker().pickImage(
        imageQuality: kImageUploadQuality,
        maxWidth: kImageMaxWidth,
        source: imgpick.ImageSource.gallery);
    if (xfile == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xfile.readAsBytes();
      final (name, mime) =
          normalizeImageUpload(xfile.name, xfile.mimeType ?? 'image/jpeg');
      final result = await uploader(name, bytes, mime);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _srcCtrl.text = result.url;
        if (_overlayCtrl.text.trim().isEmpty) _overlayCtrl.text = xfile.name;
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
            child: CachedImage(
              url: _srcCtrl.text.trim(),
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_) => const SizedBox.shrink(),
            ),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (widget.uploadMedia == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.photo_library),
                        tooltip: l10n.pickFromDevice,
                        onPressed: _pickAndUpload,
                      )),
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _overlayCtrl,
          decoration: InputDecoration(
            labelText: l10n.coverOverlay,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }
}
