import 'dart:async';

import 'package:flutter/foundation.dart';

import 'block_document.dart';

/// Owns the editor's document model and block-edit operations, decoupled from
/// the Flutter widget tree (P2-9).
///
/// [BlockEditor] delegates to this controller and rebuilds on
/// [notifyListeners]; the model itself is therefore independently unit-testable
/// without a [BuildContext]. Every mutating operation serializes the blocks and
/// reports the new HTML via [onChanged] (mirroring the previous `_emit`), so the
/// parent's [BlockEditor.onContentChanged] keeps firing exactly as before.
class EditorController extends ChangeNotifier {
  EditorController({required String initialContent, this.onChanged}) {
    _blocks = parseBlocks(initialContent);
    _lastEmitted = serializeBlocks(_blocks);
  }

  /// Fired with the freshly serialized HTML after every edit.
  final ValueChanged<String>? onChanged;

  List<ContentBlock> _blocks = [];
  int? _focusedIndex;
  String _lastEmitted = '';

  /// Current blocks. Do not mutate directly — use the edit methods.
  List<ContentBlock> get blocks => _blocks;

  /// Index of the block that holds focus, or null.
  int? get focusedIndex => _focusedIndex;

  /// Coalesces rapid edits so the (potentially expensive) downstream
  /// `onChanged` propagation fires at most once per short pause instead of on
  /// every keystroke (P3-10).
  Timer? _onChangedTimer;
  static const _onChangedDebounce = Duration(milliseconds: 100);

  /// Last serialized HTML emitted; the source of truth for change detection.
  String get content => _lastEmitted;

  void _emit() {
    _lastEmitted = serializeBlocks(_blocks);
    _scheduleOnChanged();
  }

  void _scheduleOnChanged() {
    _onChangedTimer?.cancel();
    _onChangedTimer = Timer(_onChangedDebounce, () {
      onChanged?.call(_lastEmitted);
    });
  }

  /// Applies an external content update (e.g. a post loaded in the
  /// background). Reparsed only when it differs from what we last emitted, so
  /// an echo of our own output does not reset the caret/focus.
  void updateFromExternal(String content) {
    if (content == _lastEmitted || content.trim() == _lastEmitted.trim()) return;
    // A pending debounced emit from a prior edit must not overwrite the new
    // content we are about to set (P3-10).
    _onChangedTimer?.cancel();
    _blocks = parseBlocks(content);
    _focusedIndex = null;
    _lastEmitted = serializeBlocks(_blocks);
    notifyListeners();
  }

  /// Replaces the HTML of the block at [index].
  void updateHtml(int index, String html) {
    _blocks[index].html = html;
    _emit();
    notifyListeners();
  }

  /// Inserts [block] right after the focused block (or at the end) and focuses it.
  void insert(ContentBlock block) {
    final at = _focusedIndex == null ? _blocks.length : _focusedIndex! + 1;
    _blocks.insert(at, block);
    _focusedIndex = at;
    _emit();
    notifyListeners();
  }

  /// Moves the block at [index] by [delta] (-1 up, +1 down), keeping focus with it.
  void move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _blocks.length) return;
    final b = _blocks.removeAt(index);
    _blocks.insert(target, b);
    if (_focusedIndex == index) {
      _focusedIndex = target;
    } else if (_focusedIndex == target) {
      _focusedIndex = index;
    }
    _emit();
    notifyListeners();
  }

  /// Deletes the block at [index], adjusting focus so it doesn't land on a
  /// now-missing index.
  void delete(int index) {
    _blocks.removeAt(index);
    if (_focusedIndex == index) {
      _focusedIndex = null;
    } else if (_focusedIndex != null && _focusedIndex! > index) {
      _focusedIndex = _focusedIndex! - 1;
    }
    _emit();
    notifyListeners();
  }

  /// Sets the focused block. Focus is a view concern, so this does not emit.
  void focus(int index) {
    _focusedIndex = index;
    notifyListeners();
  }

  @override
  void dispose() {
    _onChangedTimer?.cancel();
    super.dispose();
  }
}
