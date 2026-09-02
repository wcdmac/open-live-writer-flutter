# Open Live Writer

A cross-platform WordPress blog writing client (Flutter implementation) supporting Windows, Linux, macOS, iOS, and Android.

Built on the philosophy and protocol behavior of [Open Live Writer](https://github.com/OpenLiveWriter/OpenLiveWriter) (MIT License, .NET Foundation), fully rewritten in Dart/Flutter.

## Features

- **Dual-mode editor**: Visual (WYSIWYG) block editor + HTML source mode with real-time preview
  - Visual mode supports: paragraphs, headings (H1–H6), images (device upload to media library / URL), tables (add/remove rows & columns, headers), video (YouTube / MP4 / iframe embed)
  - WordPress block comments (Gutenberg markup) preserved verbatim on round-trip edits
  - Unrecognized HTML falls back to a source block and is never lost
- **Dual WordPress protocols**: XML-RPC (WordPress / MetaWeblog / MovableType / Blogger) and REST API v2 (Application Password / JWT)
- **Site auto-detection**: RSD probe, theme style detection (preview follows the blog's theme colors)
- **Full post management**: drafts / published / scheduled / private, categories, tags, excerpts, slugs, comment toggles
- **CI/CD**: GitHub Actions five-platform automated builds and Release publishing

## Credits

The architecture design and WordPress interaction protocols in this project are inspired by [Open Live Writer](https://github.com/OpenLiveWriter/OpenLiveWriter) (MIT License, Copyright .NET Foundation).

## Building

```bash
flutter pub get
flutter run          # or flutter build <platform> --release
flutter test         # run tests
```
