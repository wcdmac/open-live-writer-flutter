import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/editor/block_document.dart';

void main() {
  group('embed URL safety (M2)', () {
    test('isSafeEmbedUrl accepts http/https only', () {
      expect(isSafeEmbedUrl('https://youtu.be/abc'), isTrue);
      expect(isSafeEmbedUrl('http://example.com/a.mp4'), isTrue);
      expect(isSafeEmbedUrl('javascript:alert(1)'), isFalse);
      expect(isSafeEmbedUrl('data:text/html,<script>'), isFalse);
      expect(isSafeEmbedUrl('file:///etc/passwd'), isFalse);
      expect(isSafeEmbedUrl(''), isFalse);
    });

    test('buildVideoEmbed refuses non-http(s) sources', () {
      // A javascript: URL must never become an iframe src. The input is kept
      // as escaped, inert text instead.
      final out = buildVideoEmbed('javascript:alert(1)');
      expect(out, isNot(contains('<iframe')));
      expect(out, startsWith('<p>'));
    });

    test('buildVideoEmbed still embeds scheme-less YouTube links', () {
      // Regression guard: the safety check completes a bare link to https
      // before validating, so pasting "youtube.com/..." keeps working.
      final out = buildVideoEmbed('youtube.com/watch?v=abcdefghijk');
      expect(out, contains('wp-block-embed'));
    });

    test('buildVideoEmbed embeds https media files as <video>', () {
      final out = buildVideoEmbed('https://example.com/clip.mp4');
      expect(out, contains('<video'));
    });
  });

  group('attribute escaping (M3)', () {
    test('htmlAttr escapes quotes and angle brackets', () {
      expect(htmlAttr('x" onload="'), 'x&quot; onload=&quot;');
      expect(htmlAttr('<script>'), '&lt;script&gt;');
      expect(htmlAttr('a&b'), 'a&amp;b');
    });
  });
}
