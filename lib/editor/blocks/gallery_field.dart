part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Gallery: a responsive grid of images with per-image remove and a column
// count control. New images come from a URL prompt or device-pick upload.
// ---------------------------------------------------------------------------

class _GalleryField extends StatefulWidget {
  const _GalleryField({
    required this.block,
    required this.onChanged,
    this.uploadMedia,
  });

  final ContentBlock block;
  final ValueChanged<String> onChanged;
  final MediaUploader? uploadMedia;

  @override
  State<_GalleryField> createState() => _GalleryFieldState();
}

class _GalleryFieldState extends State<_GalleryField> {
  late GalleryData _data;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _data = parseGallery(widget.block.html) ?? GalleryData(images: const []);
  }

  void _emit() => widget.onChanged(buildGalleryHtml(_data));

  void _addImage(String url, {String alt = ''}) {
    setState(() {
      _data.images.add(GalleryImage(url: url.trim(), alt: alt.trim()));
    });
    _emit();
  }

  void _removeAt(int i) {
    setState(() => _data.images.removeAt(i));
    _emit();
  }

  Future<String?> _promptUrl(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: 'https://');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.imageUrl),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'https://'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(l10n.ok)),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

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
      final (name, mime) = normalizeImageUpload(
          xfile.name, xfile.mimeType ?? 'image/jpeg');
      final result = await uploader(name, bytes, mime);
      if (!mounted) return;
      setState(() => _uploading = false);
      _addImage(result.url, alt: xfile.name);
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
        Row(
          children: [
            Text(l10n.columnsCount,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: _data.columns > 1
                  ? () {
                      setState(() => _data.columns -= 1);
                      _emit();
                    }
                  : null,
            ),
            Text('${_data.columns}'),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: _data.columns < 8
                  ? () {
                      setState(() => _data.columns += 1);
                      _emit();
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _data.columns.clamp(1, 4),
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: _data.images.length,
          itemBuilder: (context, i) {
            final img = _data.images[i];
            return Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedImage(
                    url: img.url,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_) => const SizedBox.shrink(),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: InkWell(
                    onTap: () => _removeAt(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            if (widget.uploadMedia != null)
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickAndUpload,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_library),
                label: Text(l10n.galleryAddImage),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final url = await _promptUrl(context);
                if (url != null && url.trim().isNotEmpty && mounted) {
                  _addImage(url);
                }
              },
              icon: const Icon(Icons.link),
              label: Text(l10n.enterImageUrl),
            ),
          ],
        ),
      ],
    );
  }
}
