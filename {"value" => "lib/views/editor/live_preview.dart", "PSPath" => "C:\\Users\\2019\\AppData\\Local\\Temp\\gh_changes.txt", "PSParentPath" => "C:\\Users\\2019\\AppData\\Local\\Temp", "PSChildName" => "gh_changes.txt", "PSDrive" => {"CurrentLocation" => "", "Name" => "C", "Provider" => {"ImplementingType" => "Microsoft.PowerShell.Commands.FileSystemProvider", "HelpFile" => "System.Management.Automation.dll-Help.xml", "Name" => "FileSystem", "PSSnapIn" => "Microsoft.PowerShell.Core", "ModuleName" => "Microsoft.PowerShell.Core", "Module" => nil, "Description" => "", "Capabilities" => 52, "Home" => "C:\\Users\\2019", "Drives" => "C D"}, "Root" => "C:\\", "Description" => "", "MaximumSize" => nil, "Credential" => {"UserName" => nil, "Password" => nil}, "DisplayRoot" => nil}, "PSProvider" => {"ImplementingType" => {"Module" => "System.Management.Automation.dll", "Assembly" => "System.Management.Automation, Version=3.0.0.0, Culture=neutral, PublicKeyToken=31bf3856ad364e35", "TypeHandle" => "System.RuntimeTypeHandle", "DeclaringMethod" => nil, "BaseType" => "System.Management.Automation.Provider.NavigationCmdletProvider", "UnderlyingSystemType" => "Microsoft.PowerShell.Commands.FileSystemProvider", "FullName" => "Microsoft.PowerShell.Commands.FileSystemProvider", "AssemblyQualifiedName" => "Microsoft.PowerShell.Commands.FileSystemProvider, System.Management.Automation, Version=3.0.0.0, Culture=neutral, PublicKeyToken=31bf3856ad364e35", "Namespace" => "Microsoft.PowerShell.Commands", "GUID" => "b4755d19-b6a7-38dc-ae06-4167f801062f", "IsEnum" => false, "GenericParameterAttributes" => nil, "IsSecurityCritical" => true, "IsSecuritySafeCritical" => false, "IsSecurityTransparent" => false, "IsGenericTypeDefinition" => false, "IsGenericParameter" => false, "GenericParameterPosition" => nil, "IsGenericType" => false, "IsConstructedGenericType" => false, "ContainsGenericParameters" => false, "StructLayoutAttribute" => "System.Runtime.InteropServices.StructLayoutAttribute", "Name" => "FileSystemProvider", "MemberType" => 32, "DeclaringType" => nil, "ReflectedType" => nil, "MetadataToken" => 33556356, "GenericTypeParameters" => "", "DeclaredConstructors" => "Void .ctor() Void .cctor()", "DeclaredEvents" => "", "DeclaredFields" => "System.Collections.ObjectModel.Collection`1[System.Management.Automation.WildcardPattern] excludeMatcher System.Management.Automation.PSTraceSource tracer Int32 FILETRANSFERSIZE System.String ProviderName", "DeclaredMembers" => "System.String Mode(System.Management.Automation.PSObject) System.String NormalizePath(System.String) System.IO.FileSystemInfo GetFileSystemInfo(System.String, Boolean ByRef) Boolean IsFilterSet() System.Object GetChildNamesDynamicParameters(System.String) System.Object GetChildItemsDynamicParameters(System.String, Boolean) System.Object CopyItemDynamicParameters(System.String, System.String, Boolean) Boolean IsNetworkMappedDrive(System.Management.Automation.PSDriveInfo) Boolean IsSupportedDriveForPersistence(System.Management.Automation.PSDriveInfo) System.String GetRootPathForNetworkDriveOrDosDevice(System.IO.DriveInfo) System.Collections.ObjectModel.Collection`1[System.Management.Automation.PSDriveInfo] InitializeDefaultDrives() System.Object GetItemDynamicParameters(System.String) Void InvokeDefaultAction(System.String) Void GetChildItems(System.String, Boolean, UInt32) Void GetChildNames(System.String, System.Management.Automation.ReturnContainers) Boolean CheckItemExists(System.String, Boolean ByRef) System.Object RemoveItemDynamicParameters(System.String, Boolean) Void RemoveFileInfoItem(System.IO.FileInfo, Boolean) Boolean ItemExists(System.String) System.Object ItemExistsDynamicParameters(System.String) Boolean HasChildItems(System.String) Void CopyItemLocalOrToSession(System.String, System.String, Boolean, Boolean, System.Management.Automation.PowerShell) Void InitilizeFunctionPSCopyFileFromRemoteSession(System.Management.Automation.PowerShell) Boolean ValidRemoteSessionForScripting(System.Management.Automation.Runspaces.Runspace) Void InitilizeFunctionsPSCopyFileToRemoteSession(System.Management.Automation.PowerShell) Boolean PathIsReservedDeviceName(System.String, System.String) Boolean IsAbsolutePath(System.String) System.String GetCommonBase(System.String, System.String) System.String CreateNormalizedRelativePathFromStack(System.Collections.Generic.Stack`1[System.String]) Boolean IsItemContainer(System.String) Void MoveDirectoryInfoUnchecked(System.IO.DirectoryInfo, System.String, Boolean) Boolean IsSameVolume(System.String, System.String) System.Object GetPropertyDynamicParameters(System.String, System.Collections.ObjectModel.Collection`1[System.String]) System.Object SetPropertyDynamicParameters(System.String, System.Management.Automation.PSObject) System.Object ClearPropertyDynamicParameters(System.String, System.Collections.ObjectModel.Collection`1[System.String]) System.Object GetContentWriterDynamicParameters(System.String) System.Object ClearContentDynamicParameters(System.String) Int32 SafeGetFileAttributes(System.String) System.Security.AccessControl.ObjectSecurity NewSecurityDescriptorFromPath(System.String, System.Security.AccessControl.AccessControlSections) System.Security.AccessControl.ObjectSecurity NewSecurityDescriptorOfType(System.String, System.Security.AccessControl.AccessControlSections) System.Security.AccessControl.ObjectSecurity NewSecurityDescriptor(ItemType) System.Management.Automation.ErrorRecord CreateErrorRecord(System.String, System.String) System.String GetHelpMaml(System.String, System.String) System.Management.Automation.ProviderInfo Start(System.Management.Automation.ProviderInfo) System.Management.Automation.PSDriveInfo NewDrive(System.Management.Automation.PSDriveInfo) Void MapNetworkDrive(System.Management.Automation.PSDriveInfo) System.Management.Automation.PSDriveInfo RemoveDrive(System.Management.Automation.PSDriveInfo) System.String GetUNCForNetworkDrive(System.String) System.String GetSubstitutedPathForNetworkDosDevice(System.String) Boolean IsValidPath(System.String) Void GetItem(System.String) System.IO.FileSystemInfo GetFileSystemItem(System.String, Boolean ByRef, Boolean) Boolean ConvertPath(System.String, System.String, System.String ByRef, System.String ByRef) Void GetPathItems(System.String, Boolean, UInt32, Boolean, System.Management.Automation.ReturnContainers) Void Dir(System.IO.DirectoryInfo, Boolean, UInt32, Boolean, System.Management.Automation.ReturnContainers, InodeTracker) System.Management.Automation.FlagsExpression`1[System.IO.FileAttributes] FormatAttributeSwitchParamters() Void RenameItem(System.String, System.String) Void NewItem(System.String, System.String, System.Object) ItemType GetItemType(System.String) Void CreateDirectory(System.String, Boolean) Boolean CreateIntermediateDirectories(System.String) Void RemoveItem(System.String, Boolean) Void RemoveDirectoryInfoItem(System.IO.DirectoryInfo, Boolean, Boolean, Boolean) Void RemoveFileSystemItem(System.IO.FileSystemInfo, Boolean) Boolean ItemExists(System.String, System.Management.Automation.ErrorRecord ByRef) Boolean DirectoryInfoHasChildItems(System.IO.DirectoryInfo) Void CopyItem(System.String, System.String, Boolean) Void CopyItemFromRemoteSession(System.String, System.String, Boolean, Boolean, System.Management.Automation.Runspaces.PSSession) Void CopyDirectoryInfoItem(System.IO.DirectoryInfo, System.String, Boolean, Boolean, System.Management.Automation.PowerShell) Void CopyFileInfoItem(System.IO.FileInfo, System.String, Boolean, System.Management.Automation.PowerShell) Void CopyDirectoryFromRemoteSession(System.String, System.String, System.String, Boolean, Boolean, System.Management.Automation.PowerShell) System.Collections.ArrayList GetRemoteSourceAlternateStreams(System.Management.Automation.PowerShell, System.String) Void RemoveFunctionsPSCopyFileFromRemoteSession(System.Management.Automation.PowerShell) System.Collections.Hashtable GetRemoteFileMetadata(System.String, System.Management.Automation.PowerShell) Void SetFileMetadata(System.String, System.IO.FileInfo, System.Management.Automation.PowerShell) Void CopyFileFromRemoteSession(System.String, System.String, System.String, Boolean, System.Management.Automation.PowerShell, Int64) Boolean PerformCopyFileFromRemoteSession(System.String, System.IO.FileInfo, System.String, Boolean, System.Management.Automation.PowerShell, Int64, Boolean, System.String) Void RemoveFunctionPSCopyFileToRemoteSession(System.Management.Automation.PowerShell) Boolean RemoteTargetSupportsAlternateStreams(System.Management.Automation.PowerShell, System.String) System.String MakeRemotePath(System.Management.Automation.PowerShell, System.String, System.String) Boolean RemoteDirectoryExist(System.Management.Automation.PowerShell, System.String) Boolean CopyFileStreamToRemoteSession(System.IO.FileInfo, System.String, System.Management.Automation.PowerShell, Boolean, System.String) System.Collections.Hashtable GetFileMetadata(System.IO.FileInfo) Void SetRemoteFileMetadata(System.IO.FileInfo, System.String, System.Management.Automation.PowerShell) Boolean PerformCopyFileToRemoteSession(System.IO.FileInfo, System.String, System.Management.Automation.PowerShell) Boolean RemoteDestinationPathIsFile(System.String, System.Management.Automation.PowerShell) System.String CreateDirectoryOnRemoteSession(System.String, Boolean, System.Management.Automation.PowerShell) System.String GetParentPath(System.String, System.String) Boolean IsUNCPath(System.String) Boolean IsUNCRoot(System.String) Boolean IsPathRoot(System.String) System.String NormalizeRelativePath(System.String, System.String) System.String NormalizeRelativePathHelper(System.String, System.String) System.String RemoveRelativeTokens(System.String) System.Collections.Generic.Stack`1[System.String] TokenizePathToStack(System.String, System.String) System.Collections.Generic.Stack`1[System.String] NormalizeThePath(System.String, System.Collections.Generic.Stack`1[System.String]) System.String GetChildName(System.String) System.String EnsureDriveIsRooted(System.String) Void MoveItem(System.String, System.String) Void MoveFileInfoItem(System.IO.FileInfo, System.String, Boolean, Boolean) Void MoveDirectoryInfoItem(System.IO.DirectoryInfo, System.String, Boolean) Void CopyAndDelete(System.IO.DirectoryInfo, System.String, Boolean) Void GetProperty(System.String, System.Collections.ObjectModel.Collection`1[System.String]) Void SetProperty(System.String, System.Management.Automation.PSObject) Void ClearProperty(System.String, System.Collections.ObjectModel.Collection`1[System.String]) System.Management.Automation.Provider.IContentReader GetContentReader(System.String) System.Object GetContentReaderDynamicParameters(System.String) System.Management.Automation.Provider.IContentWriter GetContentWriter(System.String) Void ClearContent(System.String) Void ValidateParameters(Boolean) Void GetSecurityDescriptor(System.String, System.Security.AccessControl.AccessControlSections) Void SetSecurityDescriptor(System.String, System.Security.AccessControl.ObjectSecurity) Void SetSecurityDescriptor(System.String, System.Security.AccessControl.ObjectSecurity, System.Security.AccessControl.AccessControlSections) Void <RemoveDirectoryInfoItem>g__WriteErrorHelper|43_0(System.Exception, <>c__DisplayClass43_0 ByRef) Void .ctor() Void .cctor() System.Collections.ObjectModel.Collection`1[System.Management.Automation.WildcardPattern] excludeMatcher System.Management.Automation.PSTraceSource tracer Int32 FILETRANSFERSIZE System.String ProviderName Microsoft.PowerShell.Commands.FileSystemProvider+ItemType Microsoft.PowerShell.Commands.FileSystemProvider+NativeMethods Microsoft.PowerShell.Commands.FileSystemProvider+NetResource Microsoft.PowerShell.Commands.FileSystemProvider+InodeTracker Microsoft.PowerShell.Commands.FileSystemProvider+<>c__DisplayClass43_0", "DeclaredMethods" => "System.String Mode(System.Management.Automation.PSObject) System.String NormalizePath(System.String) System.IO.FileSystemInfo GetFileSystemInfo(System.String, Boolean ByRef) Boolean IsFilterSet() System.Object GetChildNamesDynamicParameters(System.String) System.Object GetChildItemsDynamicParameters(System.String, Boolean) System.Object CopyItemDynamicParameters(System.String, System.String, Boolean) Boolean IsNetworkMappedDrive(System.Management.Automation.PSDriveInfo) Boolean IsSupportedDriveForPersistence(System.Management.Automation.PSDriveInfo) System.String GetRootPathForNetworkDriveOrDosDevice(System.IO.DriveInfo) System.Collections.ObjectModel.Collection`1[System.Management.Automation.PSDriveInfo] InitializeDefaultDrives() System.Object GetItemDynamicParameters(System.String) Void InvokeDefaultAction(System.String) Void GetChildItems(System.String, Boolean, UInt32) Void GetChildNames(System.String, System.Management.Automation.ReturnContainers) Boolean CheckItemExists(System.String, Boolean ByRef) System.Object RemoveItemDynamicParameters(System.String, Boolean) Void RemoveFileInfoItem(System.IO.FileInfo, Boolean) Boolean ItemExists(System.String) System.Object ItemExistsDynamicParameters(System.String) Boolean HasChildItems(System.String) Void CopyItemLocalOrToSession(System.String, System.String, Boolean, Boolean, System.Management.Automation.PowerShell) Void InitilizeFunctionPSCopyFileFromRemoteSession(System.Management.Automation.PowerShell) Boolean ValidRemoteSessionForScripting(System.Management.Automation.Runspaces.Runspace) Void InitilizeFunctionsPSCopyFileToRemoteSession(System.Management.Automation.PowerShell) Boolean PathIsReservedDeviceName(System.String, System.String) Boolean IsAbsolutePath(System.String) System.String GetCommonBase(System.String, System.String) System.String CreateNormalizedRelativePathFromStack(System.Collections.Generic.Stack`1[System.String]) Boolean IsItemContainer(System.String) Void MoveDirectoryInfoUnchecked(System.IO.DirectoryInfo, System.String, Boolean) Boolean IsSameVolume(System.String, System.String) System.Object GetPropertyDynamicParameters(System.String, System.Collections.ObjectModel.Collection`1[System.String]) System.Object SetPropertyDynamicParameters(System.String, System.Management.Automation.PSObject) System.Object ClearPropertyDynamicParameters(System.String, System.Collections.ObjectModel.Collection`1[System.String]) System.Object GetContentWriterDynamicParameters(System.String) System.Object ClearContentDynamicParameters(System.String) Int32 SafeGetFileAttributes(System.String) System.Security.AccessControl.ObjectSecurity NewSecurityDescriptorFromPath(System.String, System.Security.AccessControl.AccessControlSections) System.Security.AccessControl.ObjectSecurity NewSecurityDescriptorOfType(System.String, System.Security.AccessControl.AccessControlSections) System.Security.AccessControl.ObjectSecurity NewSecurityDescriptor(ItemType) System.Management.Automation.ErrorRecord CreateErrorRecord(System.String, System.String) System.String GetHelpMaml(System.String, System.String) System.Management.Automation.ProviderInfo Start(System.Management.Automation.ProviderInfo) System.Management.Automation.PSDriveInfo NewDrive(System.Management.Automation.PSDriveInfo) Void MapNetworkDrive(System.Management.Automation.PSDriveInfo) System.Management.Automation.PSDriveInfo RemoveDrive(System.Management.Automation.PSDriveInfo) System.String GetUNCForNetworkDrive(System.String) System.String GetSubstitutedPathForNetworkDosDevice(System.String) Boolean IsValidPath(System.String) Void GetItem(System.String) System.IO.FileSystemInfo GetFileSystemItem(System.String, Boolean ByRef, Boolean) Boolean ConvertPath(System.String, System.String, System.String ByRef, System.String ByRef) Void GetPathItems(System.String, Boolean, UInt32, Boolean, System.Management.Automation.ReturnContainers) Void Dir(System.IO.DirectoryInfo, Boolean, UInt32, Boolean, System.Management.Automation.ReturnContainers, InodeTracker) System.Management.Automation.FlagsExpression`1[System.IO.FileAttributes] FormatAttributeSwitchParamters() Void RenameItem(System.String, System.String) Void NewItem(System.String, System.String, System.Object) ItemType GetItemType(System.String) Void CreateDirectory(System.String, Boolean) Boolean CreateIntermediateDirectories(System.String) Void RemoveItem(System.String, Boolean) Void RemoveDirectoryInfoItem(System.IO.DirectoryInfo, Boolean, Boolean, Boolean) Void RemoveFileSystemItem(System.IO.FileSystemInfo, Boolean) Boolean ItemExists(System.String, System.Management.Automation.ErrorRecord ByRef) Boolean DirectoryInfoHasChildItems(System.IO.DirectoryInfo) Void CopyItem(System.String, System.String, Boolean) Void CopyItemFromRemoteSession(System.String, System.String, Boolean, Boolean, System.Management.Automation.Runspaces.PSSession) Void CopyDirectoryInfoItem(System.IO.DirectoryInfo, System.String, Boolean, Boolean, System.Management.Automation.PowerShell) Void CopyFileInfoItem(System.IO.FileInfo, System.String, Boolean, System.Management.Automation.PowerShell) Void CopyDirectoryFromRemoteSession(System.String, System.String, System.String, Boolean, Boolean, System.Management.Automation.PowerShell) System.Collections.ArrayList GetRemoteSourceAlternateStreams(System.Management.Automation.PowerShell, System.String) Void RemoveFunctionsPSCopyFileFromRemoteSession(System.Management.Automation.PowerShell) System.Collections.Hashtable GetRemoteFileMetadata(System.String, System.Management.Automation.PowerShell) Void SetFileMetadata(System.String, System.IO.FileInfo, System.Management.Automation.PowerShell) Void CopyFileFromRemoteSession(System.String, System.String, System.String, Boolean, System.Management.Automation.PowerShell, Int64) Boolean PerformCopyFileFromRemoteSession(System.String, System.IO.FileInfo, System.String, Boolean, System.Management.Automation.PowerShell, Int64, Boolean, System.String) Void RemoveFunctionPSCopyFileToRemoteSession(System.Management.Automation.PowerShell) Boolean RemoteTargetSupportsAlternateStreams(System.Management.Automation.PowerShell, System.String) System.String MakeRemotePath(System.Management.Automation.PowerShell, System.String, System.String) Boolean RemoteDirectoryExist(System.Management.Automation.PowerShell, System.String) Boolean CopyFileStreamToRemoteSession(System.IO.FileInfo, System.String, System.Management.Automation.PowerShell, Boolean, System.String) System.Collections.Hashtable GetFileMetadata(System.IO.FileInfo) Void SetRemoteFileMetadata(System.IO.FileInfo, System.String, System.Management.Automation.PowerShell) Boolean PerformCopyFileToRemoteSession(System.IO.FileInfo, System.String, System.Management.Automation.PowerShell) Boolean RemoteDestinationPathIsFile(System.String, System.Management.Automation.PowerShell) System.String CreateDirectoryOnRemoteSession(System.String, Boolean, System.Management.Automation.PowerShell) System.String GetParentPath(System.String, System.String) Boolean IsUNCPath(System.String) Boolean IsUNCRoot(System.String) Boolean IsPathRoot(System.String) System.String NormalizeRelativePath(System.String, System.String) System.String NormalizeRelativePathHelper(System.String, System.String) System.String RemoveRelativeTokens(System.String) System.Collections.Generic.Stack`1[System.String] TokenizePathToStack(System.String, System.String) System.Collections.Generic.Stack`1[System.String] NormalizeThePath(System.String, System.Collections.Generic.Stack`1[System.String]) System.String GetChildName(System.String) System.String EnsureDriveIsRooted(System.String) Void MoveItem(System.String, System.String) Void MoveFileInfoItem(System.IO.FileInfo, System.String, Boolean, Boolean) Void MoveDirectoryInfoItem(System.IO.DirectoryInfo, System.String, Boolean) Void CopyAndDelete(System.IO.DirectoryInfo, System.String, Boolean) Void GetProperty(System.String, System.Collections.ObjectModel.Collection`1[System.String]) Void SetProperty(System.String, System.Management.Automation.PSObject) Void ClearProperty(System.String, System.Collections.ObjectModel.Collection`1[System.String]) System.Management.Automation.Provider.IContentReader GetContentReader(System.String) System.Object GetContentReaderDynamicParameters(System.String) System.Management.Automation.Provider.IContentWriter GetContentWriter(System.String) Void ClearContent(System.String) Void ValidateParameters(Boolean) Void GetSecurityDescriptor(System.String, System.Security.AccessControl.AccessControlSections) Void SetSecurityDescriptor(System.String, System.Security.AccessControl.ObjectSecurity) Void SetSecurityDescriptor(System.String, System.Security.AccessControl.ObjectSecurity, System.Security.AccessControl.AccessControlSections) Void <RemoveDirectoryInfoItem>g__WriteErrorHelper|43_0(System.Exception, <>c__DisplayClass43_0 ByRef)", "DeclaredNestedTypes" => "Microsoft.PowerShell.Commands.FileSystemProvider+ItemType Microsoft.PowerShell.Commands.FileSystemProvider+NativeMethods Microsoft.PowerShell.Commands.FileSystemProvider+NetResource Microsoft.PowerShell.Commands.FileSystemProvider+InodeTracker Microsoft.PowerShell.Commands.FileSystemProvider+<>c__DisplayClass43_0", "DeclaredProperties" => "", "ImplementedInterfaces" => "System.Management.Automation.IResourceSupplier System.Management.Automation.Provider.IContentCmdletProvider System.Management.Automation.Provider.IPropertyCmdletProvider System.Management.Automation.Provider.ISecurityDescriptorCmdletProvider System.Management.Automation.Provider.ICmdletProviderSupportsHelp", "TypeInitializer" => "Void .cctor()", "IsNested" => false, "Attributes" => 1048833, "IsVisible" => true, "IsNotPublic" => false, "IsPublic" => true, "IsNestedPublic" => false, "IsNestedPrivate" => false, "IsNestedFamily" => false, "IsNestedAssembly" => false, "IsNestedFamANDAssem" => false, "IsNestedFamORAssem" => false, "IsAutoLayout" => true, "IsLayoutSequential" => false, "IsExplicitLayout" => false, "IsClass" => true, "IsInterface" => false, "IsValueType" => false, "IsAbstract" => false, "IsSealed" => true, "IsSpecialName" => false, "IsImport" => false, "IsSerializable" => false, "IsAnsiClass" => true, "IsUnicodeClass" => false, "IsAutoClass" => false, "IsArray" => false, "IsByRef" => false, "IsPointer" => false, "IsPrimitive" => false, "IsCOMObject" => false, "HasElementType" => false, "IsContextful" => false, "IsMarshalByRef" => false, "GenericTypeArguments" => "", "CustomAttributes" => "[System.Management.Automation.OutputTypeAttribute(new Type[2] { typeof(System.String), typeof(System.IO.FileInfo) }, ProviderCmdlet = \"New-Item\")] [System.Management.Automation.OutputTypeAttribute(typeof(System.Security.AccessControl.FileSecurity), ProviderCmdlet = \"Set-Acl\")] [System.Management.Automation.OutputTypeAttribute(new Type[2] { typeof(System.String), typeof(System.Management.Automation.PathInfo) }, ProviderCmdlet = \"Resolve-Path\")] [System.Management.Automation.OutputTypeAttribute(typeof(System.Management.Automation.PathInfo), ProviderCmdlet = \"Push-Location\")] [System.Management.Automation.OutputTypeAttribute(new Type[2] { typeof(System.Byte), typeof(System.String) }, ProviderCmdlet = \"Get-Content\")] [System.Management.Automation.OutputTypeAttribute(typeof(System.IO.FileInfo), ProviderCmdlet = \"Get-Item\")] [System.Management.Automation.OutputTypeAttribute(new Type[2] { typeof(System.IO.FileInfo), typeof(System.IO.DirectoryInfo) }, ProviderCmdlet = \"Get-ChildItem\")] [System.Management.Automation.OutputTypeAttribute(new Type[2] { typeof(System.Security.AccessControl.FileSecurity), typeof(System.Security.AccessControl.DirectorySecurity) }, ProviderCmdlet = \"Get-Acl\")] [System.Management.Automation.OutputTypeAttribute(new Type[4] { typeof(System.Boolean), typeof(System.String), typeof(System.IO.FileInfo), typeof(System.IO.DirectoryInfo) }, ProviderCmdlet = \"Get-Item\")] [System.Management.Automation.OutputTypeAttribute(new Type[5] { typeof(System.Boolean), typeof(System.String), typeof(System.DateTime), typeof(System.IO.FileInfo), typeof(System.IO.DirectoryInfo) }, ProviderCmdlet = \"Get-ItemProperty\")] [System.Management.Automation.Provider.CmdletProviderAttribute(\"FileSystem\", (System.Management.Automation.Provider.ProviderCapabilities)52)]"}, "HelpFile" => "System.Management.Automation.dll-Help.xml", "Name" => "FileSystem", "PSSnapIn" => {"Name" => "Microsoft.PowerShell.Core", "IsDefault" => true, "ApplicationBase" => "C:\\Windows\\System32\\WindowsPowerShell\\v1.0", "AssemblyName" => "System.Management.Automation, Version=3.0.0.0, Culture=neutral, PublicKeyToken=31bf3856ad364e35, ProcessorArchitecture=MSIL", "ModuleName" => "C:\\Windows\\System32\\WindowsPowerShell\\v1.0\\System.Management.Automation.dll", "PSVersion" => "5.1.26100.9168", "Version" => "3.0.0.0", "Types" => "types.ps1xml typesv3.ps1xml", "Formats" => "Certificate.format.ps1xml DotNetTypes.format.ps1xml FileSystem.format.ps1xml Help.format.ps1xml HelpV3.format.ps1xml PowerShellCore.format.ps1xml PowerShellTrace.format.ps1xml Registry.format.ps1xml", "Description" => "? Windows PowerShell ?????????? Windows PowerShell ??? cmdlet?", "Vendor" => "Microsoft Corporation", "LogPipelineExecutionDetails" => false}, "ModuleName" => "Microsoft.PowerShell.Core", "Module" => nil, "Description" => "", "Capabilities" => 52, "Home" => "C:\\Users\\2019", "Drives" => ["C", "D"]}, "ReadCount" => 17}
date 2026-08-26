import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../l10n/app_localizations.dart';
import '../../services/theme_detector.dart';
import '../../editor/video_placeholder.dart';

/// Real-time preview: renders the post with Flutter's own engine
/// (no embedded browser, works identically on all five platforms),
/// styled by the detected blog theme. Subscribes to the editor's
/// debounced change stream for live updates.
class LivePreview extends StatefulWidget {
  const LivePreview({
    super.key,
    required this.content,
    required this.title,
    required this.theme,
    required this.onContentChanged,
  });

  /// Initial content.
  final String content;
  final String title;
  final BlogTheme? theme;

  /// Broadcast stream of debounced content edits.
  final Stream<String> onContentChanged;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  late String _content;
  late String _title;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _content = widget.content;
    _title = widget.title;
    _sub = widget.onContentChanged.listen((content) {
      if (mounted) setState(() => _content = content);
    });
  }

  @override
  void didUpdateWidget(LivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _title = widget.title;
    }
    // CRITICAL: keep content in sync with the widget parameter. Relying
    // solely on the debounced stream races when content is set
    // programmatically (e.g. full post loaded after opening), leaving
    // the preview permanently blank.
    if (oldWidget.content != widget.content && widget.content != _content) {
      _content = widget.content;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // Build inline CSS-ish styling for the rendered HTML widget.
    final fontFamily = theme?.fontFamily;
    final bodyStyle = TextStyle(
      fontFamily: fontFamily,
      color: _parseColor(theme?.bodyColor) ?? scheme.onSurface,
      fontSize: 17,
      height: 1.7,
    );

    return Container(
      color: _parseColor(theme?.backgroundColor) ?? scheme.surface,
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (theme?.contentWidth ?? 720).toDouble(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_title.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontFamily: fontFamily,
                                fontWeight: FontWeight.w700,
                                color: _parseColor(theme?.headingColor) ??
                                    scheme.onSurface,
                              ),
                        ),
                      ),
                    if (widget.theme?.name != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          l10n.previewTheme(widget.theme!.name!),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.outline,
                              ),
                        ),
                      ),
                    HtmlWidget(
                      _content.isEmpty
                          ? '<p style="opacity:0.5">${l10n.startWritingHint}</p>'
                          : _content,
                      textStyle: bodyStyle,
                      // <video>/<iframe>/embeds cannot be played and failed
                      // image URLs must not be silent — swap in placeholder
                      // widgets with visible loading/error states.
                      customWidgetBuilder: mediaPlaceholderBuilder,
                      customStylesBuilder: (element) {
                        switch (element.localName) {
                          case 'a':
                            return {
                              'color': theme?.linkColor ?? '#2563eb',
                              'text-decoration': 'underline',
                            };
                          case 'h1':
                          case 'h2':
                          case 'h3':
                          case 'h4':
                            return {
                              'color': theme?.headingColor ?? 'rgba(0,0,0,0.89)',
                              'font-weight': '700',
                            };
                          case 'blockquote':
                            return {
                              'border-left':
                                  '3px solid ${theme?.linkColor ?? '#2563eb'}',
                              'padding-left': '16px',
                              'opacity': '0.85',
                            };
                          case 'img':
                            return {'max-width': '100%'};
                          case 'code':
                            return {
                              'background-color': 'rgba(127,127,127,0.12)',
                              'font-family': 'monospace',
                            };
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Parses common CSS color notations (#rgb, #rrggbb, rgb(), rgba(),
/// named colors) into a Flutter [Color]. Returns null when unknown.
Color? _parseColor(String? css) {
  if (css == null) return null;
  final value = css.trim().toLowerCase();

  const named = {
    'black': 0xFF000000,
    'white': 0xFFFFFFFF,
    'red': 0xFFFF0000,
    'green': 0xFF008000,
    'blue': 0xFF0000FF,
    'gray': 0xFF808080,
    'grey': 0xFF808080,
    'orange': 0xFFFFA500,
    'yellow': 0xFFFFFF00,
  };
  if (named.containsKey(value)) return Color(named[value]!);

  final hex6 = RegExp(r'^#([0-9a-f]{6})$').firstMatch(value);
  if (hex6 != null) {
    return Color(0xFF000000 | int.parse(hex6.group(1)!, radix: 16));
  }
  final hex3 = RegExp(r'^#([0-9a-f]{3})$').firstMatch(value);
  if (hex3 != null) {
    final h = hex3.group(1)!;
    final rgb = h.split('').map((c) => c + c).join();
    return Color(0xFF000000 | int.parse(rgb, radix: 16));
  }

  final rgba = RegExp(
          r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$')
      .firstMatch(value);
  if (rgba != null) {
    final r = int.parse(rgba.group(1)!);
    final g = int.parse(rgba.group(2)!);
    final b = int.parse(rgba.group(3)!);
    final a = rgba.group(4) == null ? 1.0 : double.parse(rgba.group(4)!);
    return Color.fromARGB((a * 255).round(), r, g, b);
  }
  return null;
}
