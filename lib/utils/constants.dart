/// Named constants replacing magic numbers scattered across the editor UI.
///
/// Centralising them (audit item L1) keeps tuning in one place and stops
/// the same literal from drifting between copies.
library;

/// JPEG quality (0–100) applied when gallery images are uploaded.
const int kImageUploadQuality = 90;

/// Maximum pixel width images are resized to before upload.
const int kImageMaxWidth = 2560;

/// Debounce window for coalescing undo-history snapshots while typing.
const Duration kHistoryDebounce = Duration(milliseconds: 700);

/// Maximum retained undo/redo snapshots (ring-buffer cap).
const int kHistoryStackLimit = 100;

/// Layout breakpoint (px) above which the editor uses the wide two-pane UI.
const double kWideLayoutBreakpoint = 1000;
