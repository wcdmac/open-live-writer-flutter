part of '../block_editor.dart';

// ---------------------------------------------------------------------------
// Insert bar at the bottom of the visual editor.
// ---------------------------------------------------------------------------

class _InsertBar extends StatelessWidget {
  const _InsertBar({required this.onInsert, this.uploadMedia});

  final ValueChanged<ContentBlock> onInsert;
  final MediaUploader? uploadMedia;

  Future<void> _insertImage(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final fromDevice = uploadMedia == null
        ? false
        : await showModalBottomSheet<bool>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: Text(l10n.pickFromDevice),
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(l10n.enterImageUrl),
                    onTap: () => Navigator.of(sheetContext).pop(false),
                  ),
                ],
              ),
            ),
          );
    if (fromDevice == null || !context.mounted) return;

    if (fromDevice) {
      // Pick, upload, then insert an image block with the result URL.
      final xfile = await imgpick.ImagePicker().pickImage(
          imageQuality: kImageUploadQuality,
        maxWidth: kImageMaxWidth,
        source: imgpick.ImageSource.gallery);
      if (xfile == null || !context.mounted) return;
      // N8: uploads can take minutes on cross-border links; let the user
      // cancel instead of being locked out of the editor. The dialog stays
      // non-dismissible by barrier so a stray outside tap can't pop the wrong
      // route.
      var cancelled = false;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) => AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(l10n.uploadingImage),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(dctx).pop();
              },
              child: Text(l10n.cancel),
            ),
          ],
        ),
      );
      try {
        final bytes = await xfile.readAsBytes();
        final (name, mime) = normalizeImageUpload(
            xfile.name, xfile.mimeType ?? 'image/jpeg');
        final result = await uploadMedia!(name, bytes, mime);
        if (cancelled || !context.mounted) return;
        if (context.mounted) Navigator.of(context).pop();
        onInsert(ContentBlock(
          type: BlockType.image,
          html: buildImageHtml(result.url, xfile.name),
          wpOpen: '<!-- wp:image -->',
          wpClose: '<!-- /wp:image -->',
        ));
      } catch (e) {
        if (!cancelled && context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(mediaUploadErrorText(l10n, e))));
        }
      }
      return;
    }

    final url = await _prompt(context, l10n.imageUrl, 'https://');
    if (url == null || url.isEmpty || !context.mounted) return;
    final alt = await _prompt(context, l10n.altText, '');
    // The second prompt is another await point: the dialog's context owner
    // can be unmounted before onInsert reaches back into the editor state.
    if (!context.mounted) return;
    onInsert(ContentBlock(
      type: BlockType.image,
      html: buildImageHtml(url, alt ?? ''),
      wpOpen: '<!-- wp:image -->',
      wpClose: '<!-- /wp:image -->',
    ));
  }

  /// Video insert: device pick & upload (wp:video block) or URL embed.
  Future<void> _insertVideo(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final fromDevice = uploadMedia == null
        ? false
        : await showModalBottomSheet<bool>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.video_library),
                    title: Text(l10n.pickVideoFromDevice),
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(l10n.enterVideoUrl),
                    onTap: () => Navigator.of(sheetContext).pop(false),
                  ),
                ],
              ),
            ),
          );
    if (fromDevice == null || !context.mounted) return;

    if (fromDevice) {
      final xfile = await imgpick.ImagePicker()
          .pickVideo(source: imgpick.ImageSource.gallery);
      if (xfile == null || !context.mounted) return;
      // N8: same cancellable upload dialog as the image path.
      var cancelled = false;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) => AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(l10n.uploadingVideo)),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(dctx).pop();
              },
              child: Text(l10n.cancel),
            ),
          ],
        ),
      );
      try {
        final bytes = await xfile.readAsBytes();
        final result = await uploadMedia!(
            xfile.name, bytes, xfile.mimeType ?? 'video/mp4');
        if (cancelled || !context.mounted) return;
        if (context.mounted) Navigator.of(context).pop();
        onInsert(ContentBlock(
          type: BlockType.video,
          html: buildVideoFileHtml(result.url),
          wpOpen: '<!-- wp:video -->',
          wpClose: '<!-- /wp:video -->',
        ));
      } catch (e) {
        if (!cancelled && context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(mediaUploadErrorText(l10n, e))));
        }
      }
      return;
    }

    final url = await _prompt(context, l10n.videoUrl, 'https://');
    if (url == null || url.trim().isEmpty || !context.mounted) return;
    onInsert(ContentBlock(
      type: BlockType.video,
      html: buildVideoEmbed(url.trim()),
      wpOpen: '<!-- wp:embed -->',
      wpClose: '<!-- /wp:embed -->',
    ));
  }

  Future<String?> _prompt(BuildContext context, String title, String hint) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: hint);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.text_fields, size: 18),
            label: Text(l10n.paragraphBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.paragraph,
              html: '<p></p>',
              wpOpen: '<!-- wp:paragraph -->',
              wpClose: '<!-- /wp:paragraph -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.title, size: 18),
            label: Text(l10n.headingBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.heading,
              html: '<h2></h2>',
              wpOpen: '<!-- wp:heading -->',
              wpClose: '<!-- /wp:heading -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.image, size: 18),
            label: Text(l10n.imageBlock),
            onPressed: () => _insertImage(context),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.table_chart, size: 18),
            label: Text(l10n.tableBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.table,
              html: buildTable(),
              wpOpen: '<!-- wp:table -->',
              wpClose: '<!-- /wp:table -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.code, size: 18),
            label: Text(l10n.codeBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.code,
              html: buildCodeHtml(''),
              wpOpen: '<!-- wp:code -->',
              wpClose: '<!-- /wp:code -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.format_list_bulleted, size: 18),
            label: Text(l10n.listBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.list,
              html: buildListHtml(ListData(items: [''])),
              wpOpen: '<!-- wp:list -->',
              wpClose: '<!-- /wp:list -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.format_quote, size: 18),
            label: Text(l10n.quoteBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.quote,
              html: buildQuoteHtml(QuoteData(paragraphs: [''])),
              wpOpen: '<!-- wp:quote -->',
              wpClose: '<!-- /wp:quote -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.play_circle_outline, size: 18),
            label: Text(l10n.videoBlock),
            onPressed: () => _insertVideo(context),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.photo, size: 18),
            label: Text(l10n.coverImageBlock),
            onPressed: () => _insertCover(context),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.collections, size: 18),
            label: Text(l10n.galleryBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.gallery,
              html: buildGalleryHtml(GalleryData(images: const [])),
              wpOpen: '<!-- wp:gallery -->',
              wpClose: '<!-- /wp:gallery -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.smart_button, size: 18),
            label: Text(l10n.buttonBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.button,
              html: buildButtonHtml(ButtonData(label: l10n.button)),
              wpOpen: '<!-- wp:buttons -->',
              wpClose: '<!-- /wp:buttons -->',
            )),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.view_column, size: 18),
            label: Text(l10n.columnsBlock),
            onPressed: () => onInsert(ContentBlock(
              type: BlockType.columns,
              html: buildColumnsHtml(ColumnsData(columns: ['', ''])),
              wpOpen: '<!-- wp:columns -->',
              wpClose: '<!-- /wp:columns -->',
            )),
          ),
        ],
      ),
    );
  }

  /// Cover image insert: offer device pick (upload → embed hosted URL) or a
  /// plain URL, then insert a cover block. Mirrors [_insertImage].
  Future<void> _insertCover(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final fromDevice = uploadMedia == null
        ? false
        : await showModalBottomSheet<bool>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: Text(l10n.pickFromDevice),
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(l10n.enterImageUrl),
                    onTap: () => Navigator.of(sheetContext).pop(false),
                  ),
                ],
              ),
            ),
          );
    if (fromDevice == null || !context.mounted) return;

    if (fromDevice) {
      final xfile = await imgpick.ImagePicker().pickImage(
          imageQuality: kImageUploadQuality,
          maxWidth: kImageMaxWidth,
          source: imgpick.ImageSource.gallery);
      if (xfile == null || !context.mounted) return;
      // N8: same cancellable upload dialog as the image path.
      var cancelled = false;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) => AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(l10n.uploadingImage),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(dctx).pop();
              },
              child: Text(l10n.cancel),
            ),
          ],
        ),
      );
      try {
        final bytes = await xfile.readAsBytes();
        final (name, mime) = normalizeImageUpload(
            xfile.name, xfile.mimeType ?? 'image/jpeg');
        final result = await uploadMedia!(name, bytes, mime);
        if (cancelled || !context.mounted) return;
        if (context.mounted) Navigator.of(context).pop();
        onInsert(ContentBlock(
          type: BlockType.coverImage,
          // N7: do NOT pre-fill the cover overlay with the picked file's name
          // (e.g. "IMG_0231.jpg") — that text would be published into the post
          // unless the user remembered to clear it. Leave it empty; the user
          // adds overlay text deliberately in the focused field.
          html: buildCoverHtml(CoverData(url: result.url)),
          wpOpen: '<!-- wp:cover -->',
          wpClose: '<!-- /wp:cover -->',
        ));
      } catch (e) {
        if (!cancelled && context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(mediaUploadErrorText(l10n, e))));
        }
      }
      return;
    }

    final url = await _prompt(context, l10n.imageUrl, 'https://');
    if (url == null || url.trim().isEmpty || !context.mounted) return;
    onInsert(ContentBlock(
      type: BlockType.coverImage,
      html: buildCoverHtml(CoverData(url: url.trim())),
      wpOpen: '<!-- wp:cover -->',
      wpClose: '<!-- /wp:cover -->',
    ));
  }
}
