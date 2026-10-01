part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Video: URL field, embed builder.
// ---------------------------------------------------------------------------

/// Videos are NOT downscaled by the picker (unlike images, which pass
/// `maxWidth`/`imageQuality`), so reading one straight into memory can OOM
/// the app on a several-hundred-MB file. Reject oversized picks up front
/// instead of `readAsBytes()`-ing them whole.
const int kMaxVideoUploadBytes = 100 * 1024 * 1024;

class _VideoField extends StatefulWidget {
  const _VideoField({
    required this.block,
    required this.onChanged,
    this.uploadMedia,
  });

  final ContentBlock block;
  final ValueChanged<String> onChanged;
  final MediaUploader? uploadMedia;

  @override
  State<_VideoField> createState() => _VideoFieldState();
}

class _VideoFieldState extends State<_VideoField> {
  late final TextEditingController _url;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: firstEmbedUrl(widget.block.html) ?? '');
  }

  Future<void> _pickAndUpload() async {
    final l10n = AppLocalizations.of(context)!;
    final uploader = widget.uploadMedia;
    if (uploader == null) return;
    final xfile = await imgpick.ImagePicker()
        .pickVideo(source: imgpick.ImageSource.gallery);
    // Same disposal hazard as the image picker above.
    if (xfile == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      // Size gate before the whole file is pulled into RAM (see
      // [kMaxVideoUploadBytes]). Far larger than any realistic phone clip
      // that servers accept, but small enough to keep the process alive.
      final size = await xfile.length();
      if (size > kMaxVideoUploadBytes) {
        if (!mounted) return;
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.uploadTooLarge)));
        return;
      }
      final bytes = await xfile.readAsBytes();
      final result = await uploader(
          xfile.name, bytes, xfile.mimeType ?? 'video/mp4');
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _url.text = result.url;
      });
      // A locally uploaded file becomes a wp:video block.
      widget.block.wpOpen = '<!-- wp:video -->';
      widget.block.wpClose = '<!-- /wp:video -->';
      widget.onChanged(buildVideoFileHtml(result.url));
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
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.play_circle_outline, size: 34),
          title: Text(l10n.videoBlock),
          subtitle: Text(_url.text,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        TextField(
          controller: _url,
          decoration: InputDecoration(
              labelText: l10n.videoUrl,
              hintText: l10n.videoUrlHint,
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
                          icon: const Icon(Icons.video_library),
                          tooltip: l10n.pickVideoFromDevice,
                          onPressed: _pickAndUpload,
                        ))),
          onChanged: (v) {
            if (v.trim().isEmpty) return;
            widget.onChanged(buildVideoEmbed(v.trim()));
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }
}
