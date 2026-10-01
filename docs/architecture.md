# Architecture & conventions

Reference notes for the parts of the codebase whose contracts are not obvious
from the code alone. Several past defects came from these contracts being
implicit, so they are written down here.

## 1. Module map

| Layer | Path | Responsibility |
|-------|------|----------------|
| Models | `lib/models/` | `BlogPost` (a post), `BlogAccount` / `BlogInfo` (connection metadata) |
| Protocol | `lib/services/rest/`, `lib/services/xmlrpc/` | REST API v2 and XML-RPC clients behind one facade |
| Facade | `lib/services/blog_service.dart` | Chooses REST vs XML-RPC for the account |
| Persistence | `lib/services/account_store.dart`, `local_draft_store.dart` | Accounts (prefs + secure storage) and local drafts (prefs) |
| State | `lib/state/app_state.dart`, `editor_state.dart` | `ChangeNotifier` roots |
| Editor | `lib/editor/block_document.dart`, `block_editor.dart` | HTML ↔ block model, WYSIWYG UI |
| Views | `lib/views/` | Home dashboard, post editor, add-account |

## 2. `BlogPost` vs `LocalDraft` — the offline-copy distinction

A `LocalDraft` is one of two different things, decided by `postId`:

- **`postId == null`** → a plain new-post draft written offline.
- **`postId != null`** → an **offline copy** of an existing server post
  (`isOfflineCopy == true`), downloaded for offline editing and pushed back
  with `editPost`.

`LocalDraft.remoteModified` records when the server copy was last known to
match the stored content. It is **not** the server's own modification time.

`BlogPost.modified` (added for conflict detection) is the server's
`modified_gmt` / `post_modified_gmt`. It is `null` for dashboard list entries,
which deliberately use a lightweight `_fields` projection that excludes it.

## 3. `AppState` rules

- `refresh()` has a **re-entrancy guard** (`if (loading) return`). Overlapping
  calls from `selectAccount`/`addAccount` would otherwise duplicate fetches.
- Taxonomy fetches (categories/tags) are best-effort and must never block the
  post list — they are launched as separate futures, not bundled into one
  `Future.wait`.
- `dispose()` releases the active `BlogService` (and its `http.Client`).
- `load()` never lets an exception escape: failures go to the log and a stable
  message into `error`.

## 4. Persistence: the read-modify-write hazard

Both stores persist **one JSON array under one key** and rewrite it whole.
Therefore:

> A "failed to decode" result must **never** be treated as "no records".

`AccountStore._readAccounts()` and `LocalDraftStore._readDrafts()` are the
strict readers used by every mutation. They return `null` when nothing is
stored and **throw** when a payload exists but cannot be decoded, so the
mutation aborts instead of replacing the user's data with a single entry.

The public `loadAccounts()` / `loadDrafts()` are the tolerant readers used for
display: they degrade to an empty list but log the failure. Nothing in the
read path rewrites the key, so a corrupt payload stays recoverable on disk.

Entry-level decoding is tolerant: unusable records are skipped so one bad row
cannot take the rest down with it.

## 5. HTML contract in the editor

- Blocks whose editing surface is a plain `TextField` **with** an inline
  formatting toolbar (paragraph, heading, quote, list) hold **HTML by design** —
  the toolbar inserts `<strong>`, `<a href>`, etc. Their content is therefore
  inserted back **unescaped**. This is intentional, not an injection bug.
- Everything built by helpers in `block_document.dart` (images, code, tables,
  video embeds) is **escaped** (`htmlAttr` / `_encodeEntities`).
- Any **user-supplied URL** must be escaped with `htmlAttr` before being
  interpolated into an attribute, and validated with `isSafeEmbedUrl` before
  becoming an `iframe`/`video` source — `javascript:` and `data:` are rejected.

## 6. Error surfacing policy

Raw exception text must **not** reach the UI: protocol errors carry the blog
endpoint, account name, local paths and sometimes credential material.

Use `userFacingError(error, context: …)` (`lib/services/error_message.dart`),
which logs the detail and returns a categorised, actionable message.
Never `'$e'` in a widget or in `AppState.error`.

## 7. Testing layout

- `test/xmlrpc_*`, `test/wordpress_*` — protocol layer (MockClient injected).
- `test/block_document_test.dart`, `test/content_pipeline_test.dart` — HTML ↔
  block model.
- `test/document_safety_test.dart` — URL safety and attribute escaping.
- `test/local_draft_store_test.dart` — persistence data-loss guards.

Known gap: the widget layer (`BlockEditor`, `HomePage`) has no direct test
coverage yet; see the audit report's P2 recommendations.
