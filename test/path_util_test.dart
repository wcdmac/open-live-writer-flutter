import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/utils/path_util.dart';

void main() {
  group('displayFileName (L13 — UI must show only the name)', () {
    test('returns the final segment', () {
      expect(displayFileName('/a/b/c.md'), 'c.md');
      expect(displayFileName(r'C:\a\b\c.md'), 'c.md');
      expect(displayFileName('c.md'), 'c.md');
    });
    test('trailing separators are ignored', () {
      expect(displayFileName('/a/b/'), 'b');
      expect(displayFileName(r'C:\a\b\'), 'b');
    });
    test('root / empty degrades gracefully', () {
      expect(displayFileName('/'), '');
    });
  });

  group('desensitizePath (L13 — keep the OS username out of logs)', () {
    test('collapses a /Users/<name>/ path to ~', () {
      expect(desensitizePath('/Users/alice/Documents/x.md'),
          '~/Documents/x.md');
    });
    test('collapses a C:\\Users\\<name>\\ path to ~', () {
      expect(desensitizePath(r'C:\Users\bob\Downloads\x.md'),
          r'~\Downloads\x.md');
    });
    test('leaves non-user paths untouched', () {
      expect(desensitizePath('/Volumes/Shared/x.md'), '/Volumes/Shared/x.md');
    });
    test('never throws on arbitrary input', () {
      expect(() => desensitizePath(''), returnsNormally);
      expect(() => desensitizePath('not/a/path'), returnsNormally);
    });
  });
}
