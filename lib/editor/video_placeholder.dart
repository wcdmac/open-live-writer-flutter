import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Combined builder for media the stock HTML renderer renders poorly:
/// video/iframe/embed placeholders plus images with visible loading
/// and error states (a hot-link-blocked or non-image URL otherwise
/// fails silently as blank space).
Widget? mediaPlaceholderBuilder(dom.Element element) {
  final video = videoPlaceholderBuilder(element);
  if (video != null) return video;
  if (element.localName == 'img') {
    final src = element.attributes['src'];
    if (src == null || src.isEmpty) return null;
    return ImagePlaceholder(
      src: src,
      alt: element.attributes['alt'] ?? '',
    );
  }
  return null;
}

/// Tappable placeholder card for media the HTML renderer cannot play
/// (`<video>`, `<iframe>`, video embeds). Native playback is not viable
/// on all five target platforms, so previews show a poster card and the
/// tap opens the media externally. YouTube links show the real thumbnail.
Widget? videoPlaceholderBuilder(dom.Element element) {
  final url = switch (element.localName) {
    'video' => element.attributes['src'] ??
        element.querySelector('source')?.attributes['src'],
    'iframe' => element.attributes['src'],
    'figure' => (element.classes.contains('wp-block-embed') &&
            _isVideoEmbed(element))
        ? _embedUrl(element)
        : null,
    _ => null,
  };
  if (url == null || url.isEmpty) return null;
  return VideoPlaceholder(url: url);
}

bool _isVideoEmbed(dom.Element element) {
  final classes = element.className.toLowerCase();
  return classes.contains('is-type-video') ||
      classes.contains('provider-youtube') ||
      classes.contains('provider-vimeo');
}

String? _embedUrl(dom.Element element) {
  for (final e in element.querySelectorAll('a')) {
    final href = e.attributes['href'];
    if (href != null && href.isNotEmpty) return href;
  }
  // YouTube wp:embed keeps the plain URL as the wrapper's text content.
  final text = element.querySelector('.wp-block-embed__wrapper')?.text;
  final m = text == null ? null : RegExp(r'https?://\S+').firstMatch(text);
  return m?.group(0);
}

class VideoPlaceholder extends StatelessWidget {
  const VideoPlaceholder({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final yt = RegExp(r'(?:youtube\.com/watch\?v=|youtu\.be/)([\w-]{6,})')
            .firstMatch(url) ??
        RegExp(r'youtube\.com/embed/([\w-]{6,})').firstMatch(url);
    final thumb = yt == null
        ? null
        : 'https://i.ytimg.com/vi/${yt.group(1)}/hqdefault.jpg';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumb == null
                  ? Container(color: scheme.surfaceContainerHighest)
                  : Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(color: scheme.surfaceContainerHighest),
                    ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70),
              ),
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 36),
            ),
            // Hint that the card opens the media externally.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black45,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Image with a visible loading spinner and a descriptive error card —
/// a failed URL (hot-link protection, non-image page URL, http:// on
/// iOS, unreachable host) must not collapse into silent blank space.
class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({super.key, required this.src, this.alt = ''});

  final String src;
  final String alt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Image.network(
        src,
        width: double.infinity,
        fit: BoxFit.scaleDown,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Container(
                height: 160,
                alignment: Alignment.center,
                child: progress.expectedTotalBytes == null
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!,
                      ),
              ),
        errorBuilder: (_, _, _) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.errorContainer),
            borderRadius: BorderRadius.circular(8),
            color: scheme.errorContainer.withValues(alpha: 0.25),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.broken_image_outlined,
                    color: scheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(l10n.imageLoadFailed,
                        style: TextStyle(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                            fontSize: 13))),
              ]),
              const SizedBox(height: 6),
              Text(src,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
