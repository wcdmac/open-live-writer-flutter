/// Named constants replacing magic numbers scattered across the editor UI.
///
/// Centralising them (audit item L1) keeps tuning in one place and stops
/// the same literal from drifting between copies.
library;

/// JPEG quality (0–100) applied when gallery images are uploaded.
const int kImageUploadQuality = 90;

/// Maximum pixel width images are resized to before upload.
const double kImageMaxWidth = 2560.0;

/// Debounce window for coalescing undo-history snapshots while typing.
const Duration kHistoryDebounce = Duration(milliseconds: 700);

/// Maximum retained undo/redo snapshots (ring-buffer cap).
const int kHistoryStackLimit = 100;

/// Layout breakpoint (px) above which the editor uses the wide two-pane UI.
const double kWideLayoutBreakpoint = 1000;

/// Number of posts fetched per dashboard page (P1-5 pagination). A full
/// page back implies more posts exist, so the list offers "load more".
const int kPostPageSize = 50;

/// Allowed wall-clock skew when deciding whether a server post changed after
/// an offline copy was taken (P3-13). Server and device clocks rarely match
/// exactly, so a change within this window is not treated as a conflict.
const Duration kConflictClockSkew = Duration(seconds: 1);
